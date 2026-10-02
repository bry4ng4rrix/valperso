import pytest

from app.core.permissions import RoleName


@pytest.fixture
def alice(factory):
    return factory.vendeur(factory.store(), username="alice")


@pytest.fixture
def bob(factory):
    return factory.admin(username="bob")


def start_private(client, factory, sender, recipient):
    return client.post(
        "/api/v1/chat/conversations",
        headers=factory.headers(sender),
        json={"type": "PRIVATE", "member_ids": [recipient.id]},
    )


def test_private_conversation_is_created_once(client, factory, alice, bob):
    first = start_private(client, factory, alice, bob)
    again = start_private(client, factory, bob, alice)

    assert first.status_code == 201
    assert again.status_code == 200
    assert again.json()["id"] == first.json()["id"]
    assert sorted(m["user"]["username"] for m in first.json()["members"]) == ["alice", "bob"]


def test_messages_and_unread_count(client, factory, alice, bob):
    conversation_id = start_private(client, factory, alice, bob).json()["id"]

    sent = client.post(
        f"/api/v1/chat/conversations/{conversation_id}/messages",
        headers=factory.headers(alice),
        json={"content": "Bonjour Bob, il reste du riz ?"},
    )
    unread_before = client.get("/api/v1/chat/conversations", headers=factory.headers(bob)).json()[0][
        "unread_count"
    ]
    client.post(f"/api/v1/chat/conversations/{conversation_id}/read", headers=factory.headers(bob))
    unread_after = client.get("/api/v1/chat/conversations", headers=factory.headers(bob)).json()[0][
        "unread_count"
    ]
    messages = client.get(
        f"/api/v1/chat/conversations/{conversation_id}/messages", headers=factory.headers(bob)
    ).json()

    assert sent.status_code == 201
    assert sent.json()["content"] == "Bonjour Bob, il reste du riz ?"  # le chat n'est pas mis en majuscules
    assert (unread_before, unread_after) == (1, 0)
    assert messages["total"] == 1


def test_non_member_cannot_read_conversation(client, factory, alice, bob):
    conversation_id = start_private(client, factory, alice, bob).json()["id"]
    intruder = factory.vendeur(factory.store())

    response = client.get(
        f"/api/v1/chat/conversations/{conversation_id}/messages", headers=factory.headers(intruder)
    )

    assert response.status_code == 403


def test_group_conversation_requires_a_name(client, factory, alice, bob):
    headers = factory.headers(alice)
    no_name = client.post(
        "/api/v1/chat/conversations", headers=headers, json={"type": "GROUP", "member_ids": [bob.id]}
    )
    named = client.post(
        "/api/v1/chat/conversations",
        headers=headers,
        json={"type": "GROUP", "name": "Équipe Analakely", "member_ids": [bob.id]},
    )
    assert no_name.status_code == 422
    assert named.status_code == 201 and named.json()["name"] == "équipe analakely"


def test_only_author_can_delete_a_message(client, factory, alice, bob):
    conversation_id = start_private(client, factory, alice, bob).json()["id"]
    message_id = client.post(
        f"/api/v1/chat/conversations/{conversation_id}/messages",
        headers=factory.headers(alice),
        json={"content": "Message à supprimer"},
    ).json()["id"]

    by_bob = client.delete(f"/api/v1/chat/messages/{message_id}", headers=factory.headers(bob))
    by_alice = client.delete(f"/api/v1/chat/messages/{message_id}", headers=factory.headers(alice))
    messages = client.get(
        f"/api/v1/chat/conversations/{conversation_id}/messages", headers=factory.headers(bob)
    ).json()["items"]

    assert by_bob.status_code == 403
    assert by_alice.status_code == 204
    assert messages[0]["is_deleted"] is True and messages[0]["content"] is None


def test_cannot_start_conversation_with_unknown_user_or_self(client, factory, alice):
    headers = factory.headers(alice)
    unknown = client.post(
        "/api/v1/chat/conversations", headers=headers, json={"type": "PRIVATE", "member_ids": [999999]}
    )
    self_chat = client.post(
        "/api/v1/chat/conversations", headers=headers, json={"type": "PRIVATE", "member_ids": [alice.id]}
    )
    assert unknown.status_code == 404
    assert self_chat.status_code == 400
