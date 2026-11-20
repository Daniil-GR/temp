# Atlas — Earth & Place

Static, English-language educational website for **atlas.dateihafen.xyz**.

## Contents

- `atlas/site/`: 30 publicly served files: 16 HTML pages including eight articles, local CSS/JavaScript, original SVG illustrations, sitemap and robots.txt.
- `deploy-atlas.sh`: separate shell installer for an existing nginx-selfsteal Docker HTML mount.

The existing root `site/`, `deploy.sh`, `README.md` and `NGINX-EXAMPLE.md` are **not modified**.

## Non-disruptive installation

On the VPS that already runs `nginx-selfsteal`:

```sh
cd /root/temp
git pull --ff-only
sudo sh deploy-atlas.sh inspect --domain atlas.dateihafen.xyz
sudo sh deploy-atlas.sh stage
```

`stage` discovers the Docker host bind mount for `/var/www/html` and stages Atlas into `/var/www/html/atlas-earth` (inside the container), leaving the active site and services untouched. To use a dedicated existing nginx vhost, point that vhost's `root` to `/var/www/html/atlas-earth` after confirming your running configuration.

## Explicitly replace a default root placeholder

**Only if** `nginx -T` confirms that the site you intend to replace uses `/var/www/html` directly, and that you are prepared for all domains sharing that webroot to display Atlas:

```sh
sudo sh deploy-atlas.sh publish --confirm-root-replacement
```

The script makes a timestamped backup outside the served webroot of the files that it overwrites, then writes the new HTML/static assets and installs `index.html` last. Files unrelated to Atlas remain untouched. To roll back the most recent publish:

```sh
sudo sh deploy-atlas.sh rollback --confirm-root-replacement
```

Use `--webroot /absolute/host/path` only when you know the right host-side HTML directory; otherwise mount discovery is automatic. Other commands: `help` and `inspect`.

**Important:** The installer never edits or reloads nginx, TLS certificates, Certbot, DNS, Reality/SNI, rw-core, Docker Compose, or ports 80/443. For a new HTTPS hostname you must separately configure the correct existing vhost, certificate, and ingress routing. Prefer dedicated vhost roots on shared nodes.
