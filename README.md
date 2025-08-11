# GraphQLCop EX - Security Audit Tool for GraphQL (Elixir)

<p align="center">
  <img src="./graphql_cop_ex_logo.png" alt="GraphQLCop EX Logo" width="220" />
</p>

**Author:** Syed Imam

GraphQLCop EX is an Elixir-based security audit utility for GraphQL APIs, inspired by the original Python GraphQL Cop.  
It is built specifically for Elixir projects, integrates seamlessly with the [Absinthe](https://hexdocs.pm/absinthe) package, and can be run as a Mix task.

---

## ✨ Features

GraphQLCop EX detects common GraphQL security issues including:

- **Alias Overloading** (DoS)
- **Batch Queries** (DoS)
- **GET-based Queries** (CSRF)
- **POST-based Queries with URL-encoded Payloads** (CSRF)
- **GraphQL Tracing / Debug Modes** (Information Leakage)
- **Field Duplication** (DoS)
- **Field Suggestions** (Information Leakage)
- **GraphiQL Exposure** (Information Leakage)
- **Introspection Enabled** (Information Leakage)
- **Directive Overloading** (DoS)
- **Circular Queries via Introspection** (DoS)
- **Mutation Support over GET** (CSRF)

---

## 📦 Installation

Add `graphql_cop_ex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:graphql_cop_ex, "~> 0.1.0"}
  ]
end
```

Fetch dependencies:

```bash
mix deps.get
```

---

## 🚀 Running as a Mix Task

Run GraphQLCop EX directly from your Elixir project:

```bash
mix graphql_cop.scan --url https://myapp.com/graphql
```

### Options

| Option     | Description |
|------------|-------------|
| `--url`    | Target GraphQL endpoint |
| `--header` | Add custom headers (JSON string) |
| `--proxy`  | Route requests through a proxy |
| `--debug`  | Include test names in headers |
| `--format` | Output format (`text` or `json`) |

Example with custom headers and proxy:

```bash
mix graphql_cop.scan --url https://api.example.com/graphql   --header '{"Authorization": "Bearer token_here"}'   --proxy http://127.0.0.1:8080
```

---

## 🛠 Example Output

```plaintext
[HIGH] Introspection Query Enabled (Information Leakage)
[LOW] GraphQL Playground UI (Information Leakage)
[HIGH] Alias Overloading with 100+ aliases is allowed (Denial of Service)
[HIGH] Queries are allowed with 1000+ of the same repeated field (Denial of Service)
```

JSON output example:

```json
[
  {
    "title": "Directive Overloading",
    "description": "Multiple duplicated directives allowed in a query",
    "impact": "Denial of Service",
    "result": true,
    "severity": "HIGH",
    "color": "red",
    "curl_verify": "curl -X POST -H \"Content-Type: application/json\" -d '{"query": "query { __typename @aa@aa@aa }"}' 'https://myapp.com/graphql'"
  }
]
```

---

## 🔧 Usage in CI/CD

You can integrate GraphQLCop EX into your CI pipeline to automatically check GraphQL endpoints before deployment:

```yaml
# GitHub Actions example
jobs:
  security_scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      - run: mix deps.get
      - run: mix graphql_cop.scan --url https://myapp.com/graphql --format json
```

---

## 📚 Documentation

Once published to HexDocs, documentation will be available at:  
[https://hexdocs.pm/graphql_cop_ex](https://hexdocs.pm/graphql_cop_ex)

---

## 🛡 Disclaimer

This tool is intended for security testing of **your own** GraphQL endpoints or systems you have permission to audit.  
Unauthorized testing of systems you don't own may violate laws.

---

## 👨‍💻 Author

**Syed Imam**  