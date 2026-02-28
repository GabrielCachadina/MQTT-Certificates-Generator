# MQTT Certificate Generator

This is a "small" bash script that lets you generate MQTT over TLS certificates.

## Requirements
- `openssl`: To generate the certificates
- `mosquitto`: To test the connections
- `tree`: To list your files, not necessary.

## What It Generates
- Certificate Authority (CA)
- Server certificate (IP or domain)
- Client certificates
- Mosquitto-compatible password file

## Options
### Create Project
Creates a new project, generating the server certificates associated with an IP or domain name.

```bash
#? 1
Creating new project...
Enter project name: Hetzner-VPS
Enter server hostname (IP or domain): mqtt.gabrielcachadina.com
---
Certificate request self-signature ok
subject=C=ES, ST=Badajoz, L=Badajoz, O=SScertificate, OU=Server, CN=mqtt.gabrielcachadina.com
Project 'Hetzner-VPS' created.
Server certificate issued for: mqtt.gabrielcachadina.com
```
Note that the location and organization are hardcoded, you may change them with the variables:
```
COUNTRY="ES"
STATE="Badajoz"
CITY="Badajoz"
ORG="SScertificate"
```
### Add a Client
Adds a client to a project, generating its certificates associated with a name and password. This will also create a `passwd` at the projects root folder.

You may add as many clients as you like and later on define (manually) their permissions with an `aclfile`, that will follow this structure:
```
user username1  
topic write #  
topic read #  
  
user username2  
topic read test/#
```

### Test MQTT
Select a Project and a client to either Publish or Subscribe to a topic.
