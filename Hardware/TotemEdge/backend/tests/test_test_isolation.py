"""The suite itself must refuse hosted connections, even with leaked settings."""

import socket

import pytest


@pytest.mark.parametrize(
    "host", ["example.invalid", "203.0.113.1", "::ffff:203.0.113.1"]
)
def test_external_dns_and_connections_are_blocked(host):
    with pytest.raises(OSError, match="External network"):
        socket.getaddrinfo(host, 443)
    with socket.socket() as connection:
        with pytest.raises(OSError, match="External network"):
            connection.connect((host, 443))
        with pytest.raises(OSError, match="External network"):
            connection.connect_ex((host, 443))
