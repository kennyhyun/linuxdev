# Linuxdev

Boot up Linux development env using Vagrant

## This repo is in development

It's not recommended to use yet.

## Why?

Docker is necessary for developing nowadays. But if you are not using Linux as the OS, it requires VM for Docker engine.

I was using Linux in Virtualbox for many years and found that was quite nice and had no problem for using docker in it.
In the other hand, Docker Desktop, I found couple of issue with using Docker Desktop in Windows recently.

### Docker vs VM

#### Docker

- Watching files in the host is not working
- Hyper-v is not returning unused memory frequently so the host is easy to struggle with memory.

#### VM

Virtualbox seems to run many containers more stable and does not apply much pressure to the host memory.
And there are less issues in developing in Linux than Windows

### For Mac Users

There would be some advantage for Mac users as well

- Easily backup/cleanup VM/dev env
- The dev env is a sandbox
- Reference environment for Linux env
- Run linux GUI apps
- Docker is running Linux VM already, why not?

And if you are familiar with the command line, Using Linux makes more senses than using Docker Desktop.

- Share VM when you need bootcamp to windows
- Access to docker host
- Unlimited access to host(Linux VM) root directory
- Faster host(Linux VM) volume sharing
- Free

## How would it be like setting up the Linux dev environment?

:warning: Note that this script will disable WSL2.

1. Unzip or git clone this repo
    - https://github.com/kennyhyun/linuxdev/archive/refs/heads/main.zip
1. Run a script
    1. Install host dependencies and dev tools
        - Windows; Open powershell as Admin
          - disable hyper-v
          - VSCode
          - Windows Terminal
          - gitbash with unix tools
          - Other tools like DB clients (optional)
        - Mac
          - VSCode
          - iTerm2
          - Rectangle
          - Other tools like DB clients (optional)
        - Common
          - vagrant
          - virtualbox
    1. Bootup vagrant with provision
        - Latest Debian Linux
        - Install Docker
    1. input username
    1. Run ssh scripts into VM to bootstrap, top half
        - Create a user with UID 1000 and sudoer
        - Create ssh credentials and show public key
        - install basic devtools from external [dotfiles project](https://github.com/kennyhyun/dotfiles)

After finishing bootstrap, you can ssh into Linux dev env

```bash
ssh linuxdev
```

## External dotfiles

You can fork this repo and replace the git submodule to your own dotfiles repo.

## Additional Goals

- Docker support for the host
  - create docker certificates
  - install docker tools for the host
    - docker-cli
    - docker-compose


## Install

### Windows 10 users

#### setup.ps1

> :warning: **Note that this script will disable WSL2.**
>
> Please backup any required files before running.

Right click windows menu and click Windows Powershell (Admin)

```powershell
Set-ExecutionPolicy RemoteSigned
```

Run the setup script in the directory of this repo

```powershell
\Users\xxx\linuxdev\setup.ps1
```

** Running setup script again will check updates and install if newer version found

##### bootstrap.sh

Open Windows Terminal for Gitbash or just Git Bash

```bash
/c/Users/xxx/linuxdev/bootstrap.sh
```

This will create virtualbox machine and bootup and config

If finished successfully, you will get ssh into by

```bash
ssh vagrant
```

##### Map network drive from the machine

Virtualbox machine has IP of 192.168.99.123
and it shares Projects directory so Host machine can see the files in it.

\\192.168.99.123\Projects

** Windows git global config should turn filemode off


## License

[MIT License](https://github.com/kennyhyun/linuxdev/blob/main/LICENSE)
