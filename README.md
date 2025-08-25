# Authentik

![Build, scan & push](https://github.com/Polarix-Containers/authentik/actions/workflows/build/badge.svg)

### Features & usage
- Unprivileged image: you should check your volumes' permissions (eg `/data`), default UID/GID is 200001.
- ⚠️ Unlike upstream's container, this image does **not** use FIPS cryptography.
- ⚠️ This image has only been tested to work with OIDC. All other authentication methods ae untested.

### Licensing
- The code in this repository is licensed under the Apache license. 😇
- Authentik is licensed under a combination of different licenses. See upstream's notice [here](https://github.com/goauthentik/authentik/blob/main/LICENSE). 
- Any image built by Polarix Containers is provided under the combination of license terms resulting from the use of individual packages.