# 💫 Supernova: Multi-Protocol UDP Script

Supernova is a setup script that supports the automatic setup of multiple Udp based proxy protocols. It aims to ease the setup of private proxy nodes to bypass GFI/GFW and is not intended for production use, May everyone have access to the free and open internet!

## 🌟 Supported Protocols

Supernova currently supports the following protocols:

> I do not own these protocols. Supernova is simply setting them up using the documentation from their official repositories.

- **Hysteria v2**
- **Tuic v5**
- **Brook**
- **Mieru**
- **Juicity**
- **Naive**

## 📚 Key Features

- **Customization for Hysteria**: Customizable obfuscation and masquarade

- **IPv6 Configuration**: Provides an ipv6 config if your server supports it

- **Docker Compatibility**: Most of the protocols run on docker for ease of management and security

- **Automatic Certificate Generation**: Wether you have a domain or not supernova will generate a certificate for you which will be saved in `certs/` or `domain_certs/`

- **Configurations**: All of the configurations are saved in the related folder in the project directory.

## 🌟 Contribution

Feel free to contribute, report issues, or suggest improvements. We welcome your feedback and contributions to make Supernova even better!

## ⚙️ Setup

Enter the following commands in your terminal

```shell
git clone https://github.com/meower1/Supernova.git
cd Supernova
bash supernova.sh
```
