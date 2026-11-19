# Connecting Cloudenza Notes to an existing Selfsteal nginx instance

The included `deploy.sh` intentionally **does not** edit your existing nginx, rw-core, RemnaNode, Docker Compose or certificates. Real production layouts vary; blindly changing a running Reality ingress can interrupt every existing connection.

## 1. Inventory the node first

```sh
sudo sh deploy.sh inspect --domain YOUR_NEW_SUBDOMAIN --ip YOUR_SECONDARY_IP
docker inspect nginx-selfsteal --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'
docker inspect nginx-selfsteal --format '{{json .HostConfig.PortBindings}}'
sudo ss -lntp | grep -E '(:80|:443)[[:space:]]'
sudo grep -RniE 'server_name|listen|root|ssl_certificate|proxy_protocol' /opt/nginx-selfsteal/conf.d 2>/dev/null
```

Verify that the secondary IPv4 is assigned to the server. If not, follow the provider's network configuration and reboot instructions before modifying any listeners.

## 2. Install the static site

```sh
sudo sh deploy.sh install
```

For a common Docker Selfsteal layout, the static files end up at:

- Host: `/opt/nginx-selfsteal/html/cloudenza-notes/`
- Container: `/var/www/html/cloudenza-notes/`

If nginx mounts a different host directory at `/var/www/html`, the installer will discover that mount automatically. Nothing is removed from the existing webroot.

## 3. Publish the hostname and get a certificate

Create an **A record** for your chosen hostname, pointing to the secondary IPv4. Do not publish an AAAA record unless this host can actually serve the site over IPv6. Make sure the provider-assigned secondary IP is configured locally and traffic reaches the server.

A certificate for the previous hostname is not sufficient unless its SAN explicitly includes the new hostname.

Use your existing certificate manager, or issue a new certificate after the hostname's HTTP-01 challenge is correctly served over port 80. Another option is DNS-01 if you manage the DNS zone. Do not expect the certificate to be issued without domain ownership validation.

For an existing Docker nginx volume mapping `./ssl:/etc/nginx/ssl`, add the new PEM files into the existing host-side `ssl` directory, with restrictive key permissions. Arrange renewal/reload separately.

## 4. Adapt an nginx virtual host

These are **examples, not drop-in production configuration**. Adjust the `listen` directives to match the nginx process you discover.

For the HTTP host, serving the challenge and redirecting other paths only after HTTPS works:

```nginx
server {
    listen 80;
    server_name YOUR_NEW_SUBDOMAIN;
    root /var/www/html/cloudenza-notes;

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        try_files $uri =404;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

For a Selfsteal nginx that already listens on the shared Unix TLS socket with PROXY protocol:

```nginx
server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    server_name YOUR_NEW_SUBDOMAIN;

    ssl_certificate     /etc/nginx/ssl/notes-fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/notes-privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/html/cloudenza-notes;
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ /\\. {
        return 404;
    }
}
```

The `proxy_protocol` token must match the existing Selfsteal routing. Some installations use a loopback TCP TLS listener instead of a Unix socket; **do not add a second competing listener on the same socket/port without checking the current configuration**. In particular, don't change xver or a Reality target just because this example uses a socket.

Do not assume that Docker port 80 is exposed on the new IP. Inspect existing port bindings. If the old container publishes only the original address, account for that when setting up an HTTP-01 challenge.

If the node uses the documented Unix socket with PROXY protocol and the certificate is already in the existing SSL volume, the installer can create, test and reload this vhost automatically:

```sh
sudo sh deploy.sh activate \
  --domain YOUR_NEW_SUBDOMAIN \
  --cert-file notes-fullchain.pem \
  --key-file notes-privkey.pem
```

This command will refuse to run if it cannot verify the expected socket or find a certificate matching the hostname. It does not provision or renew the certificate.

## 5. Reality / Selfsteal ingress

The public TCP/443 listener is often owned by the existing Reality/rw-core process rather than nginx. This means adding a normal nginx `listen 202.x.x.x:443` may conflict. Configure the existing ingress to accept the chosen domain/SNI and forward appropriate web traffic to the correct nginx TLS listener, **using the active installation's actual target and xver**. Avoid starting a second TLS listener on an occupied IP:port.

The webroot installation alone does not configure the VPN inbound's SNI, XHTTP path, external IPv4 binding or certificate. Those require inspecting the current RemnaNode/Reality profile.

## 6. Validate before switching traffic

```sh
docker exec nginx-selfsteal nginx -t
docker exec nginx-selfsteal test -f /var/www/html/cloudenza-notes/index.html
dig +short A YOUR_NEW_SUBDOMAIN
curl -I --resolve YOUR_NEW_SUBDOMAIN:443:YOUR_SECONDARY_IP https://YOUR_NEW_SUBDOMAIN/
```

If nginx configuration validation passes, a non-disruptive nginx config reload is typically:

```sh
docker exec nginx-selfsteal nginx -s reload
```

Do **not** reload until you have reviewed the actual config. `curl --resolve` tests the requested IP with the new hostname and SNI but cannot by itself prove Reality client routing works.

## Rollback

The installer saves the previous `cloudenza-notes` directory as a timestamped tarball in a `backups-cloudenza` sibling directory when it is redeployed. Restore only that specific directory if required. It never overwrites another site's existing index or config.
