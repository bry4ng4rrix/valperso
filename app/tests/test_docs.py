def test_health(client):
    assert client.get("/api/v1/health").json() == {"status": "ok"}


def test_documentation_pages_are_available(client):
    assert client.get("/docs").status_code == 200
    assert client.get("/redoc").status_code == 200


def test_every_route_is_versioned_and_documented(client):
    schema = client.get("/openapi.json").json()

    assert all(path.startswith("/api/v1/") for path in schema["paths"])
    for path, operations in schema["paths"].items():
        for method, operation in operations.items():
            assert operation.get("summary"), f"{method.upper()} {path} sans summary"
            assert any(code.startswith("2") for code in operation["responses"]), f"{method} {path}"


def test_all_modules_are_exposed(client):
    schema = client.get("/openapi.json").json()
    prefixes = {path.split("/")[3] for path in schema["paths"]}
    assert prefixes == {
        "auth", "users", "roles", "permissions", "stores", "categories", "products", "stock",
        "stock-transfers", "customers", "sales", "payments", "cash", "dashboard", "chat", "audit", "health",
    }  # fmt: skip


def test_sale_creation_documents_its_errors(client):
    create_sale = client.get("/openapi.json").json()["paths"]["/api/v1/sales"]["post"]
    assert {"201", "400", "401", "403", "404", "422"} <= set(create_sale["responses"])
    assert create_sale["description"]
