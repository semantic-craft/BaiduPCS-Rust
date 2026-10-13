//! Read only desktop configuration validator. Never starts a server or loads account state.
use baidu_netdisk_rust::config::AppConfig;

fn validate(text: &str) -> Result<(), ()> {
    let config: AppConfig = toml::from_str(text).map_err(|_| ())?;
    if config.server.host != "127.0.0.1" || config.server.port != 18888 || config.autobackup.enabled {
        return Err(());
    }
    config.download.validate_download_dir().map_err(|_| ())?;
    config.share_direct_download.validate_temp_dir().map_err(|_| ())?;
    config.filesystem.validate().map_err(|_| ())?;
    Ok(())
}

fn main() {
    let valid = std::env::args().nth(1)
        .and_then(|path| std::fs::read_to_string(path).ok())
        .is_some_and(|text| validate(&text).is_ok());
    // Do not print parser errors or config values: config can contain private proxy settings.
    std::process::exit(if valid { 0 } else { 2 });
}

#[cfg(test)]
mod tests {
    use super::*;
    fn saved_config() -> AppConfig {
        let mut config = AppConfig::default();
        config.server.host = "127.0.0.1".into();
        config.server.port = 18888;
        config.autobackup.enabled = false;
        config.download.download_dir = std::env::temp_dir();
        config
    }
    #[test]
    fn supports_full_upstream_serialization_with_nested_tables() {
        let text = toml::to_string_pretty(&saved_config()).unwrap();
        assert!(text.contains("[network.proxy]"));
        assert!(validate(&text).is_ok());
    }
    #[test]
    fn rejects_schema_failure_without_falling_back() {
        assert!(validate("[server]\nhost='127.0.0.1'\nport=18888\n[autobackup]\nenabled=false").is_err());
        assert!(validate("not toml").is_err());
    }
    #[test]
    fn rejects_remote_bind_and_automatic_backup() {
        let mut config = saved_config();
        config.server.host = "0.0.0.0".into();
        assert!(validate(&toml::to_string_pretty(&config).unwrap()).is_err());
        config.server.host = "127.0.0.1".into();
        config.autobackup.enabled = true;
        assert!(validate(&toml::to_string_pretty(&config).unwrap()).is_err());
    }
}
