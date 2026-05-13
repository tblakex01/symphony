const GREETING: &str = "Hello, world!";

fn main() {
    println!("{GREETING}");
}

#[cfg(test)]
mod tests {
    use super::GREETING;

    #[test]
    fn greeting_matches_expected_output_text() {
        assert_eq!(GREETING, "Hello, world!");
    }
}
