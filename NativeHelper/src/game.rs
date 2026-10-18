//! Fixed registry: callers cannot inject Store IDs or package identities.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Game { Dungeons, Bedrock }
impl Game {
    pub fn parse(id: &str) -> Result<Self,std::io::Error> { match id { "dungeons2"=>Ok(Self::Dungeons), "bedrock"=>Ok(Self::Bedrock), _=>Err(std::io::Error::other("Game invalid")) } }
    pub fn id(self)-> &'static str { match self { Self::Dungeons=>"dungeons2",Self::Bedrock=>"bedrock" } }
    pub fn store_id(self)-> &'static str { match self { Self::Dungeons=>"9P5786PJB9RP",Self::Bedrock=>"9NBLGGH2JHXJ" } }
    pub fn baseline(self)-> &'static str { match self { Self::Dungeons=>"1.1.2.0",Self::Bedrock=>"1.26.5203.0" } }
    pub fn content_id(self)-> &'static str { match self { Self::Dungeons=>"c1c08142-2be1-4620-b13b-d84d58bd730d",Self::Bedrock=>"7792d9ce-355a-493c-afbd-768f4a77c3b0" } }
    pub fn tested_package_version(self)-> &'static str { match self {
        Self::Dungeons=>"1.1.2.0.ce1e7dbd-8b08-4b46-83c8-dfede30bd3f4",
        Self::Bedrock=>"1.26.5203.0.4650c7c5-9163-48e9-9e89-6a5584d9833f"
    } }
    pub fn validate_install(self,version:&str,experimental:bool)->Result<(),std::io::Error> {
        if !experimental || (self==Self::Dungeons && version=="1.1.1.0") { return self.validate(version); }
        let parse=|v:&str|->Result<Vec<u16>,std::io::Error>{
            let parts:Vec<_>=v.split('.').collect();
            if parts.len()!=4 || parts.iter().any(|s|s.is_empty()||!s.bytes().all(|b|b.is_ascii_digit())) {return Err(std::io::Error::other("PACKAGE_VERSION_INVALID"))}
            parts.iter().map(|s|s.parse::<u16>().map_err(|_|std::io::Error::other("PACKAGE_VERSION_INVALID"))).collect()
        };
        if parse(version)? < parse(self.baseline())? {return Err(std::io::Error::other("BEDROCK_VERSION_TOO_OLD"))} Ok(())
    }
    pub fn validate(self,version:&str)->Result<(),std::io::Error> {
        let parts:Vec<_>=version.split('.').collect();
        if parts.len()!=4 || parts.iter().any(|s|s.is_empty()||!s.bytes().all(|b|b.is_ascii_digit())||s.parse::<u16>().is_err()) {return Err(std::io::Error::other("PACKAGE_VERSION_INVALID"))}
        let values:Vec<u16>=parts.iter().map(|s|s.parse().unwrap()).collect();
        let base:Vec<u16>=self.baseline().split('.').map(|s|s.parse().unwrap()).collect();
        if self==Self::Bedrock && values<base {return Err(std::io::Error::other("BEDROCK_VERSION_TOO_OLD"))}
        if values!=base && !(self==Self::Dungeons && version=="1.1.1.0") {return Err(std::io::Error::other("BEDROCK_COMPATIBILITY_UNVERIFIED"))}Ok(())
    }
}
#[cfg(test)]mod tests{use super::*;#[test]fn registry_and_version_gate(){assert_eq!(Game::Bedrock.store_id(),"9NBLGGH2JHXJ");assert!(Game::Bedrock.validate("1.26.5203.0").is_ok());for v in ["1.26.5202.0","1.27.0.0","bad","1.26.5203","+1.26.5203.0"]{assert!(Game::Bedrock.validate(v).is_err());}assert!(Game::parse("../bedrock").is_err());}}

#[cfg(test)] mod install_tests {
 use super::*;
 #[test] fn explicit_trial_and_tested_revision_contract() {
  for (game,newer) in [(Game::Dungeons,"1.1.3.0"),(Game::Bedrock,"1.27.0.0")] {
   assert!(game.validate_install(newer,false).is_err());
   assert!(game.validate_install(newer,true).is_ok());
   for bad in ["0.0.0.0","1.2.3","1.+2.3.4","1.2.3.65536","../game"] {assert!(game.validate_install(bad,true).is_err());}
   let (version,revision)=crate::package::normalize_version(game.tested_package_version()).unwrap();
   assert_eq!(version,game.baseline());
   let pins:std::collections::HashMap<String,String>=serde_json::from_str(include_str!("package-pins.json")).unwrap();
   assert!(pins.contains_key(&format!("{}:{}",game.content_id(),revision.unwrap())));
  }
 }
}
