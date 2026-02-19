use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;

fn read_required_env(key: &str) -> String {
    env::var(key).expect(&format!("{} not set", key))
}

fn read_and_validate(path: &str) -> String {
    let content = fs::read_to_string(path).expect(&format!("Failed to read {}", path));
    let trimmed = content.trim().to_string();
    if trimmed.is_empty() {
        eprintln!("Error: {} is empty", path);
        std::process::exit(1);
    }
    trimmed
}

fn main() -> std::io::Result<()> {
    // Template Placeholders
    const P_EMAIL_USER_REV = "__EMAIL_USER_REV__";
    const P_EMAIL_DOMAIN_REV = "__EMAIL_DOMAIN_REV__";
    const P_EMAIL_NOSCRIPT = "__EMAIL_NOSCRIPT__";
    const P_PHONE_REV = "__PHONE_REV__";
    const P_PHONE_NOSCRIPT = "__PHONE_NOSCRIPT__";
    const P_NAME_REV = "__NAME_REV__";
    const P_NAME_NOSCRIPT = "__NAME_NOSCRIPT__";

    let email_path = read_required_env("IMPRESSUM_EMAIL_FILE");
    let phone_path = read_required_env("IMPRESSUM_PHONE_FILE");
    let name_path = read_required_env("IMPRESSUM_NAME_FILE");
    let template_path = read_required_env("IMPRESSUM_TEMPLATE_FILE");
    let output_path = env::var("IMPRESSUM_OUTPUT_FILE")
        .unwrap_or_else(|_| "/run/impressum/impressum.html".to_string());

    let email = read_and_validate(&email_path);
    let phone = read_and_validate(&phone_path);
    let name = read_and_validate(&name_path);

    let (user_part, domain_part) = email.split_once('@').expect("Invalid email format");
    let user_rev: String = user_part.chars().rev().collect();
    let domain_rev: String = domain_part.chars().rev().collect();
    let phone_rev: String = phone.chars().rev().collect();
    let name_rev: String = name.chars().rev().collect();

    let template = fs::read_to_string(&template_path)?;

    // Validate template placeholders
    for placeholder in [
        P_EMAIL_USER_REV,
        P_EMAIL_DOMAIN_REV,
        P_EMAIL_NOSCRIPT,
        P_PHONE_REV,
        P_PHONE_NOSCRIPT,
        P_NAME_REV,
        P_NAME_NOSCRIPT
    ] {
        if !template.contains(placeholder) {
            eprintln!("Warning: Template missing placeholder {}", placeholder);
        }
    }

    let content = template
        .replace(P_EMAIL_USER_REV, &user_rev)
        .replace(P_EMAIL_DOMAIN_REV &domain_rev)
        .replace(P_EMAIL_NOSCRIPT, &email)
        .replace(P_PHONE_REV, &phone_rev)
        .replace(P_PHONE_NOSCRIPT, &phone)
        .replace(P_NAME_REV, &name_rev)
        .replace(P_NAME_NOSCRIPT, &name);

    fs::write(&output_path, content)?;

    let mut perms = fs::metadata(&output_path)?.permissions();
    // Ensure the file is world-readable so Caddy (running as 'caddy' user)
    // can serve it, regardless of the root user's umask.
    perms.set_mode(0o644);
    fs::set_permissions(&output_path, perms)?;

    Ok(())
}
