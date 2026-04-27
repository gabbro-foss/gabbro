//! Generic CSV importer.
//!
//! Parses CSV exports from arbitrary password managers into
//! Gabbro vault entries. Treats all input as untrusted.

/// Preview of a parsed CSV file — headers and up to 3 sample rows.
/// Returned by [`sniff_csv`] for Flutter's mapping UI.
pub struct CsvPreview {
    pub headers: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

/// Configuration for mapping CSV columns to Gabbro entry fields.
/// Any column not mapped here becomes a custom field on the entry.
pub struct CsvImportConfig {
    pub title_col:     Option<String>,
    pub url_col:       Option<String>,
    pub username_col:  Option<String>,
    pub password_col:  Option<String>,
    pub notes_col:     Option<String>,
    pub favourite_col: Option<String>,
}

/// A single imported entry — flat struct ready for conversion to LoginEntry.
pub struct CsvEntry {
    pub title:         String,
    pub url:           String,
    pub username:      String,
    pub password:      String,
    pub notes:         Option<String>,
    pub favourite:     bool,
    pub custom_fields: Vec<(String, String)>,
}

/// Import all rows from a CSV string using the provided field mapping.
/// Returns one [`CsvEntry`] per data row.
pub fn import_csv(input: &str, config: &CsvImportConfig) -> Result<Vec<CsvEntry>, String> {
    if input.len() > 10 * 1024 * 1024 {
        return Err("CSV file exceeds 10 MB limit".to_string());
    }

    let input = input.strip_prefix('\u{FEFF}').unwrap_or(input);
    let mut lines = input.lines();
    let header_line = lines.next().ok_or("CSV input is empty")?;
    let headers = parse_csv_line(header_line);
    if headers.is_empty() {
        return Err("CSV has no headers".to_string());
    }

    // Build a lookup: column name → index
    let col_index = |name: &str| -> Option<usize> {
        headers.iter().position(|h| h == name)
    };

    // Identify which indices are claimed by the config
    let title_idx     = config.title_col.as_deref().and_then(col_index);
    let url_idx       = config.url_col.as_deref().and_then(col_index);
    let username_idx  = config.username_col.as_deref().and_then(col_index);
    let password_idx  = config.password_col.as_deref().and_then(col_index);
    let notes_idx     = config.notes_col.as_deref().and_then(col_index);
    let favourite_idx = config.favourite_col.as_deref().and_then(col_index);

    let claimed: Vec<usize> = [
        title_idx, url_idx, username_idx,
        password_idx, notes_idx, favourite_idx,
    ]
    .iter()
    .filter_map(|i| *i)
    .collect();

    let mut entries = Vec::new();

    for line in lines {
        if line.trim().is_empty() {
            continue;
        }
        let fields = parse_csv_line(line);

        let get = |idx: Option<usize>| -> String {
            idx.and_then(|i| fields.get(i))
               .map(|s| s.as_str())
               .unwrap_or("")
               .to_string()
        };

        let title = {
            let t = get(title_idx);
            if !t.is_empty() {
                t
            } else {
                let u = get(url_idx);
                if !u.is_empty() { u } else { "MISSING TITLE".to_string() }
            }
        };

        let notes = {
            let n = get(notes_idx);
            if n.is_empty() { None } else { Some(n) }
        };

        let favourite = normalise_favourite(&get(favourite_idx));

        // Unclaimed columns become custom fields
        let custom_fields = headers.iter().enumerate()
            .filter(|(i, _)| !claimed.contains(i))
            .map(|(i, name)| {
                let value = fields.get(i)
                    .map(|s| s.as_str())
                    .unwrap_or("")
                    .to_string();
                (name.clone(), value)
            })
            .collect();

        entries.push(CsvEntry {
            title,
            url:      get(url_idx),
            username: get(username_idx),
            password: get(password_idx),
            notes,
            favourite,
            custom_fields,
        });
    }

    Ok(entries)
}

/// Sniff the headers and first few rows of a CSV string.
/// Returns an error if the input is empty or has no headers.
/// Parse a single CSV line into fields, handling quoted fields containing commas.
/// Trims leading/trailing whitespace from each field.
/// Treats `"None"` and `""` as empty string.
fn parse_csv_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;

    for ch in line.chars() {
        match ch {
            '"' => in_quotes = !in_quotes,
            ',' if !in_quotes => {
                fields.push(normalise_field(current.trim()));
                current = String::new();
            }
            _ => current.push(ch),
        }
    }
    fields.push(normalise_field(current.trim()));
    fields
}

fn normalise_field(value: &str) -> String {
    if value.eq_ignore_ascii_case("none") {
        String::new()
    } else {
        value.to_string()
    }
}

/// Normalise a favourite field value to a bool.
/// Truthy: "1", "yes", "true" (case-insensitive). Everything else: false.
fn normalise_favourite(value: &str) -> bool {
    matches!(
        value.to_ascii_lowercase().as_str(),
        "1" | "yes" | "true"
    )
}

pub fn sniff_csv(input: &str) -> Result<CsvPreview, String> {
    let input = input.strip_prefix('\u{FEFF}').unwrap_or(input);
    let mut lines = input.lines();

    let header_line = lines.next().ok_or("CSV input is empty")?;
    let headers = parse_csv_line(header_line);
    if headers.is_empty() {
        return Err("CSV has no headers".to_string());
    }

    let rows = lines
        .take(3)
        .map(parse_csv_line)
        .collect();

    Ok(CsvPreview { headers, rows })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_CSV: &str = "\
uid, name, login, password, type, number, comments, favourite
001, \"Visa\", None, \"secret sauce\", \"card\", \"123456781298\", \"active\", None
002, \"google\", \"joe.black@google.com\", \"my supa dupa secret\", \"login\", None, None, \"yes\"
003, \"github\", \"ssh\", \"ssh public key\", \"login\", None, \"my github repo\", 1";

    #[test]
    fn sniff_returns_correct_headers() {
        let preview = sniff_csv(SAMPLE_CSV).unwrap();
        assert_eq!(preview.headers, vec![
            "uid", "name", "login", "password",
            "type", "number", "comments", "favourite"
        ]);
    }

    #[test]
    fn sniff_returns_up_to_three_rows() {
        let preview = sniff_csv(SAMPLE_CSV).unwrap();
        assert_eq!(preview.rows.len(), 3);
    }

    #[test]
    fn sniff_normalises_none_to_empty_string() {
        let preview = sniff_csv(SAMPLE_CSV).unwrap();
        // row 0: uid=001, name=Visa, login="", password=secret sauce
        // "None" in login column should become ""
        assert_eq!(preview.rows[0][2], "");
    }

    #[test]
    fn sniff_empty_input_returns_error() {
        let result = sniff_csv("");
        assert!(result.is_err(), "expected error for empty input");
    }

    #[test]
    fn import_missing_title_falls_back_to_url() {
        let csv = "name,url,password\n,https://example.com,secret";
        let config = CsvImportConfig {
            title_col:     Some("name".to_string()),
            url_col:       Some("url".to_string()),
            password_col:  Some("password".to_string()),
            username_col:  None,
            notes_col:     None,
            favourite_col: None,
        };
        let entries = import_csv(csv, &config).unwrap();
        assert_eq!(entries[0].title, "https://example.com");
    }

    #[test]
    fn import_missing_title_and_url_gives_missing_title() {
        let csv = "name,password\n,secret";
        let config = CsvImportConfig {
            title_col:     Some("name".to_string()),
            url_col:       None,
            password_col:  Some("password".to_string()),
            username_col:  None,
            notes_col:     None,
            favourite_col: None,
        };
        let entries = import_csv(csv, &config).unwrap();
        assert_eq!(entries[0].title, "MISSING TITLE");
    }

    #[test]
    fn import_favourite_normalisation() {
        let csv = "name,fav\nfirst,yes\nsecond,1\nthird,true\nfourth,no\nfifth,None\nsixth,0";
        let config = CsvImportConfig {
            title_col:     Some("name".to_string()),
            favourite_col: Some("fav".to_string()),
            url_col:       None,
            username_col:  None,
            password_col:  None,
            notes_col:     None,
        };
        let entries = import_csv(csv, &config).unwrap();
        assert!(entries[0].favourite,  "yes should be true");
        assert!(entries[1].favourite,  "1 should be true");
        assert!(entries[2].favourite,  "true should be true");
        assert!(!entries[3].favourite, "no should be false");
        assert!(!entries[4].favourite, "None should be false");
        assert!(!entries[5].favourite, "0 should be false");
    }

    #[test]
    fn import_unmapped_columns_become_custom_fields() {
        let config = default_config();
        let entries = import_csv(SAMPLE_CSV, &config).unwrap();
        let visa = &entries[0];
        // uid, type, number are unmapped
        let keys: Vec<&str> = visa.custom_fields.iter()
            .map(|(k, _)| k.as_str())
            .collect();
        assert!(keys.contains(&"uid"),    "uid should be a custom field");
        assert!(keys.contains(&"type"),   "type should be a custom field");
        assert!(keys.contains(&"number"), "number should be a custom field");
    }

    #[test]
    fn import_handles_quoted_comma_in_field() {
        let csv = "name,password\n\"Bank, Gold Card\",secret";
        let config = CsvImportConfig {
            title_col:    Some("name".to_string()),
            password_col: Some("password".to_string()),
            url_col:       None,
            username_col:  None,
            notes_col:     None,
            favourite_col: None,
        };
        let entries = import_csv(csv, &config).unwrap();
        assert_eq!(entries[0].title, "Bank, Gold Card");
    }

    #[test]
    fn import_strips_utf8_bom() {
        // Excel on Windows prepends a UTF-8 BOM to every CSV export
        let csv = "\u{FEFF}name,password\nVisa,secret";
        let config = CsvImportConfig {
            title_col:     Some("name".to_string()),
            password_col:  Some("password".to_string()),
            url_col:       None,
            username_col:  None,
            notes_col:     None,
            favourite_col: None,
        };
        let entries = import_csv(csv, &config).unwrap();
        assert_eq!(entries[0].title, "Visa");
    }

    #[test]
    fn sniff_strips_utf8_bom_from_headers() {
        let csv = "\u{FEFF}name,password\nVisa,secret";
        let preview = sniff_csv(csv).unwrap();
        assert_eq!(preview.headers[0], "name");
    }

    #[test]
    fn import_row_with_extra_columns_is_handled() {
        // Row has more fields than headers — extra fields ignored cleanly
        let csv = "name,password\nVisa,secret,extra1,extra2";
        let config = CsvImportConfig {
            title_col:     Some("name".to_string()),
            password_col:  Some("password".to_string()),
            url_col:       None,
            username_col:  None,
            notes_col:     None,
            favourite_col: None,
        };
        let entries = import_csv(csv, &config).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].title, "Visa");
        assert_eq!(entries[0].custom_fields.len(), 0,
            "extra columns beyond header count should be ignored");
    }

    #[test]
    fn import_rejects_oversized_input() {
        let big = "a".repeat(11 * 1024 * 1024);
        let result = import_csv(&big, &default_config());
        assert!(result.is_err(), "expected error for oversized input");
    }

    fn default_config() -> CsvImportConfig {
        CsvImportConfig {
            title_col:     Some("name".to_string()),
            url_col:       None,
            username_col:  Some("login".to_string()),
            password_col:  Some("password".to_string()),
            notes_col:     Some("comments".to_string()),
            favourite_col: Some("favourite".to_string()),
        }
    }

    #[test]
    fn import_maps_basic_fields() {
        let config = CsvImportConfig {
            title_col:     Some("name".to_string()),
            url_col:       None,
            username_col:  Some("login".to_string()),
            password_col:  Some("password".to_string()),
            notes_col:     Some("comments".to_string()),
            favourite_col: Some("favourite".to_string()),
        };
        let entries = import_csv(SAMPLE_CSV, &config).unwrap();
        assert_eq!(entries.len(), 3);
        let visa = &entries[0];
        assert_eq!(visa.title, "Visa");
        assert_eq!(visa.username, "");
        assert_eq!(visa.password, "secret sauce");
        assert_eq!(visa.favourite, false);
    }
}