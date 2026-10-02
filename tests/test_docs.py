def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_documentation_pages_are_available(client):
    assert client.get("/docs").status_code == 200
    assert client.get("/redoc").status_code == 200


def test_openapi_documents_all_modules_and_errors(client):
    schema = client.get("/openapi.json").json()

    prefixes = {path.split("/")[3] for path in schema["paths"] if path.startswith("/api/v1/")}
    assert prefixes == {
        "auth", "users", "roles", "permissions", "stores", "categories", "products",
        "stock", "sales", "payments", "cash", "dashboard", "chat", "audit",
    }  # fmt: skip
    create_sale = schema["paths"]["/api/v1/sales"]["post"]
    assert {"201", "400", "401", "403", "404", "422"} <= set(create_sale["responses"])
    assert create_sale["description"]
    assert "HTTPBearer" in schema["components"]["securitySchemes"]
