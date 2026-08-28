FROM nginx:1.27-alpine

# Self-signed cert for the SSO portal, generated at build time rather than
# committed -- no private key belongs in git. The subject is deliberately
# corporate-looking: it is what a player reads out of `nmap --script ssl-cert`
# or `openssl s_client` during recon, and the CN is the first place the
# `donerup.htb` domain name surfaces (spec S3).
RUN apk add --no-cache openssl \
    && mkdir -p /etc/nginx/certs \
    && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -subj "/C=NL/O=Donerup B.V./OU=IT Service Desk/CN=donerup.htb" \
        -addext "subjectAltName=DNS:donerup.htb,DNS:sso.donerup.htb,DNS:localhost" \
        -keyout /etc/nginx/certs/donerup.key \
        -out /etc/nginx/certs/donerup.crt \
    && chmod 600 /etc/nginx/certs/donerup.key

COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80 443
