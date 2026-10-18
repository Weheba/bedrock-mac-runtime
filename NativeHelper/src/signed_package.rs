//! Authenticate retail containers before any parser/decryptor consumes their data.
//! The public-only RSA anchor is recovered from the SHA256-pinned official GDK.
use std::{fs::File, io::{self, Read, Seek, SeekFrom}, path::Path};
use rsa::{BigUint, Pss, RsaPublicKey};
use sha2::{Digest, Sha256};

const PAGE: usize = 4096;
const ENTRIES: u64 = 170;
const KEY: &[u8] = include_bytes!("trust/microsoft-retail-games.rsa");
const KEY_SHA256: &str = "183f0ae05431e4ad91554e88946967c872997227dbe6c85116f5fd2fd2d1229e";
fn rejected() -> io::Error { io::Error::other("PACKAGE_AUTHENTICITY_FAILED") }
fn unsupported() -> io::Error { io::Error::other("PACKAGE_FORMAT_UNSUPPORTED") }
fn u32_at(bytes: &[u8], offset: usize) -> u32 { u32::from_le_bytes(bytes[offset..offset+4].try_into().unwrap()) }
fn u64_at(bytes: &[u8], offset: usize) -> u64 { u64::from_le_bytes(bytes[offset..offset+8].try_into().unwrap()) }

fn retail_key() -> io::Result<RsaPublicKey> {
    let digest: String = Sha256::digest(KEY).iter().map(|b| format!("{b:02x}")).collect();
    if digest != KEY_SHA256 || KEY.len() != 539 || &KEY[..4] != b"RSA1" ||
       [u32_at(KEY,4),u32_at(KEY,8),u32_at(KEY,12),u32_at(KEY,16),u32_at(KEY,20)] != [4096,3,512,0,0] {
        return Err(rejected());
    }
    RsaPublicKey::new(BigUint::from_bytes_be(&KEY[27..]), BigUint::from_bytes_be(&KEY[24..27])).map_err(|_| rejected())
}

fn verify_signature(header: &[u8; PAGE], key: &RsaPublicKey) -> io::Result<()> {
    key.verify(Pss::new_with_salt::<Sha256>(32), &Sha256::digest(&header[512..]), &header[..512]).map_err(|_| rejected())
}

pub struct SignedLayout { tree_start: u64, data_pages: u64, root: [u8;32] }

/// Signature, identity and version are checked before trusting any length field.
pub fn verify_header(header: &[u8; PAGE], id: uuid::Uuid, version: &str) -> io::Result<SignedLayout> {
    verify_signature(header, &retail_key()?)?;
    layout(header,id,version)
}

fn layout(header: &[u8; PAGE], id: uuid::Uuid, version: &str) -> io::Result<SignedLayout> {
    if &header[512..520] != b"msft-xvd" || uuid::Uuid::from_bytes_le(header[544..560].try_into().unwrap()) != id { return Err(rejected()); }
    let numbers: Vec<_> = header[0x3bc..0x3c4].chunks_exact(2).map(|b|u16::from_le_bytes(b.try_into().unwrap())).rev().collect();
    let signed_version = numbers.iter().map(u16::to_string).collect::<Vec<_>>().join(".");
    if signed_version != version { return Err(rejected()); }
    // This is the fixed, encrypted retail layout supported by our extractor.
    // Resilient/dynamic/embedded layouts need their own integrity implementation.
    if u32_at(header,0x208) != 0x41 || u32_at(header,0x280) != 0 ||
       u32_at(header,0x288) != 0 || u32_at(header,0x294) != 0 || header[0x470] > 16 { return Err(unsupported()); }
    let lengths = [u64_at(header,0x218), u32_at(header,0x28c) as u64, u32_at(header,0x290) as u64];
    if lengths.iter().any(|n| *n > 32*1024*1024*1024) { return Err(unsupported()); }
    let data_pages: u64 = lengths.iter().map(|n|n.div_ceil(PAGE as u64)).sum();
    if data_pages == 0 || data_pages > 32*1024*1024*1024/PAGE as u64 { return Err(unsupported()); }
    Ok(SignedLayout { tree_start: (3 + header[0x470] as u64)*PAGE as u64, data_pages, root: header[0x240..0x260].try_into().unwrap() })
}

fn level_sizes(mut pages: u64) -> io::Result<Vec<u64>> {
    if pages == 0 || pages > ENTRIES.pow(4) { return Err(unsupported()); }
    let mut result=vec![];
    loop { pages=pages.div_ceil(ENTRIES); result.push(pages); if pages==1 { result.reverse(); return Ok(result); } }
}

/// Check every intermediate node, including the 4-byte data-unit values in leaves,
/// then every stored data page against the signed root. Never just trust leaves.
fn verify_tree(source: &mut (impl Read + Seek), layout: &SignedLayout, size: u64, mut progress: impl FnMut(u64,u64)) -> io::Result<()> {
    let sizes=level_sizes(layout.data_pages)?;
    let tree_pages: u64=sizes.iter().sum();
    let tree_bytes=tree_pages.checked_mul(PAGE as u64).ok_or_else(unsupported)?;
    if tree_bytes > 256*1024*1024 { return Err(unsupported()); }
    let end=layout.tree_start.checked_add(tree_bytes).and_then(|n|n.checked_add(layout.data_pages*PAGE as u64)).ok_or_else(unsupported)?;
    if end != size { return Err(rejected()); }
    source.seek(SeekFrom::Start(layout.tree_start))?;
    let mut tree=vec![0;tree_bytes as usize]; source.read_exact(&mut tree)?;
    if Sha256::digest(&tree[..PAGE]).as_slice() != layout.root { return Err(rejected()); }
    let mut offsets=vec![0u64];
    for count in sizes.iter().take(sizes.len()-1) { offsets.push(offsets.last().unwrap()+count); }
    for level in 1..sizes.len() {
        for index in 0..sizes[level] {
            let entry=((offsets[level-1]+index/ENTRIES)*PAGE as u64+index%ENTRIES*24) as usize;
            let child=((offsets[level]+index)*PAGE as u64) as usize;
            if Sha256::digest(&tree[child..child+PAGE])[..24] != tree[entry..entry+24] { return Err(rejected()); }
        }
    }
    let leaves=*offsets.last().unwrap();
    let mut first=0;
    let mut chunk=vec![0;ENTRIES as usize*PAGE];
    while first < layout.data_pages {
        let count=(layout.data_pages-first).min(ENTRIES);
        source.read_exact(&mut chunk[..count as usize*PAGE])?;
        for index in 0..count {
            let entry=((leaves+(first+index)/ENTRIES)*PAGE as u64+(first+index)%ENTRIES*24) as usize;
            let start=index as usize*PAGE;
            if Sha256::digest(&chunk[start..start+PAGE])[..20] != tree[entry..entry+20] { return Err(rejected()); }
        }
        first+=count; progress(first*PAGE as u64, layout.data_pages*PAGE as u64);
    }
    Ok(())
}

pub fn verify_file(path: &Path, id: uuid::Uuid, version: &str, size: u64, progress: impl FnMut(u64,u64)) -> io::Result<()> {
    let mut file=File::open(path)?;
    if file.metadata()?.len()!=size { return Err(rejected()); }
    let mut header=[0;PAGE]; file.read_exact(&mut header)?;
    let layout=verify_header(&header,id,version)?;
    let mut reserved=[0;PAGE*2]; file.read_exact(&mut reserved)?;
    if reserved.iter().any(|b|*b!=0) { return Err(unsupported()); }
    // Mutable region-presence bytes are not consumed by the extractor. Their
    // length is signed; all extracted metadata/content is covered by the tree.
    verify_tree(&mut file,&layout,size,progress)
}

#[cfg(test)] mod tests {
    use super::*;
    use rsa::pkcs8::DecodePublicKey;
    use std::io::Cursor;

    fn synthetic(count: u64) -> (Vec<u8>, SignedLayout) {
        let sizes=level_sizes(count).unwrap();
        let mut levels: Vec<Vec<Vec<u8>>>=vec![];
        let mut child: Vec<Vec<u8>>=(0..count).map(|n|vec![(n%256) as u8;PAGE]).collect();
        let data=child.concat();
        for size in sizes.iter().rev() {
            let mut pages=vec![vec![0;PAGE];*size as usize];
            let length=if levels.is_empty() {20}else{24};
            for (index,page) in child.iter().enumerate() {
                let entry=index%ENTRIES as usize*24;
                pages[index/ENTRIES as usize][entry..entry+length].copy_from_slice(&Sha256::digest(page)[..length]);
            }
            child=pages.clone(); levels.insert(0,pages);
        }
        let root=Sha256::digest(&levels[0][0]).into();
        let mut bytes: Vec<u8>=levels.into_iter().flatten().flatten().collect(); bytes.extend(data);
        (bytes,SignedLayout {tree_start:0,data_pages:count,root})
    }

    #[test] fn synthetic_signature_binds_every_header_byte_and_production_rejects_test_key() {
        let header: &[u8;PAGE]=include_bytes!("../tests/fixtures/synthetic-signed-header.bin");
        let key=RsaPublicKey::from_public_key_der(include_bytes!("../tests/fixtures/synthetic-signing-public.der")).unwrap();
        let id=uuid::Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap();
        verify_signature(header,&key).unwrap();
        layout(header,id,"1.1.2.0").unwrap();
        for offset in [0,511,512,0x240,0x3bc,4095] {
            let mut changed=*header;changed[offset]^=1;
            assert!(verify_signature(&changed,&key).is_err());
        }
        assert!(verify_header(header,id,"1.1.2.0").is_err());
        assert!(layout(header,uuid::Uuid::nil(),"1.1.2.0").is_err());
        assert!(layout(header,id,"1.1.3.0").is_err());
    }
    #[test] fn signed_layout_rejects_unimplemented_layouts_and_excessive_lengths() {
        let header: &[u8;PAGE]=include_bytes!("../tests/fixtures/synthetic-signed-header.bin");
        let id=uuid::Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap();
        for offset in [0x208,0x280,0x288,0x294,0x470] {
            let mut changed=*header;changed[offset]=255;
            assert!(layout(&changed,id,"1.1.2.0").is_err());
        }
        let mut changed=*header;changed[0x218..0x220].copy_from_slice(&u64::MAX.to_le_bytes());
        assert!(layout(&changed,id,"1.1.2.0").is_err());
    }
    #[test] fn authenticate_root_intermediate_nodes_units_and_every_content_page() {
        let (bytes,layout)=synthetic(171); let size=bytes.len() as u64;
        let signed_header: &[u8;PAGE]=include_bytes!("../tests/fixtures/synthetic-signed-header.bin");
        assert_eq!(layout.root,&signed_header[0x240..0x260]);
        verify_tree(&mut Cursor::new(&bytes),&layout,size,|_,_|{}).unwrap();
        for offset in [0,PAGE+5,PAGE+20,3*PAGE+7,bytes.len()-1] {
            let mut changed=bytes.clone();changed[offset]^=1;
            assert!(verify_tree(&mut Cursor::new(changed),&layout,size,|_,_|{}).is_err());
        }
        assert!(verify_tree(&mut Cursor::new(&bytes[..bytes.len()-1]),&layout,size,|_,_|{}).is_err());
        assert!(verify_tree(&mut Cursor::new(&bytes),&layout,size+1,|_,_|{}).is_err());
    }
    #[test] fn tree_run_boundaries_and_three_levels() {
        for count in [1,170,171,28901] {
            let (bytes,layout)=synthetic(count);
            verify_tree(&mut Cursor::new(&bytes),&layout,bytes.len() as u64,|_,_|{}).unwrap();
        }
        assert!(level_sizes(0).is_err());assert!(level_sizes(ENTRIES.pow(4)+1).is_err());
    }
}
