# Linuxdev

Boot up Linux development env using Vagrant

**:warning: This repo is still in development** 


## Why?

Docker is necessary for developing nowadays. But if you are not using Linux as the OS, it requires VM for Docker engine.

I was using Linux in Virtualbox for many years and found that was quite nice and had no problem for using docker in it.
In the other hand, Docker Desktop, I found couple of issue with using Docker Desktop in Windows recently.

### Docker Desktop vs VM

#### Docker Desktop

- Watching files in the host is not working
- Hyper-v is not returning unused memory frequently so the host can be struggling with memory.

#### VM

- Virtualbox seems to run many containers more stable and does not apply much pressure to the host memory.
- There are less issues in developing in Linux than Windows

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

## Setting up the Linux dev environment

:warning: Note for Windows users: The script will disable Hyper-v (WSL2).

### Running scripts

1. Unzip or git clone this repo
    - https://github.com/kennyhyun/linuxdev/archive/refs/heads/main.zip
1. Run setup scripts
    - Windows
        1. Install host dependencies and dev tools
            - Open powershell as Admin and run `setup.ps1`
        1. Bootup vagrant with provision
            - Open terminal (git bash) and run `bootstrap.sh`
    - Mac
        1. Install host dependencies and dev tools
            - Open teminal and run `setup.sh`
        1. Bootup vagrant with provision
            - continue to run `bootstrap.sh`
1. Wait until bootstrap.sh does
    - input username to use in the VM
    - Install latest Debian Linux
    - Install Docker
    - Create a user with UID 1000 and sudoer
    - ohmyzsh
    - expose samba share, `Projects`
    - generate id_rsa key and show public key
    - add ssh config for linuxdev

It's okay to repeat this bootstrap script.

### After finished bootstrap

Copy and paste ssh public key to use in Github and so on

Now you can ssh into Linux dev env

```bash
ssh linuxdev
```

Run `/vagrant/init_dotfiles.sh` to continue setting up dotfiles in ssh.

It installs basic devtools from external [dotfiles project](https://github.com/kennyhyun/dotfiles)

You can override repo by `DOTFILE_REPO=git@github.com:kennyhyun/dotfiles.git`

### Commands after setup

- `vagrant halt` to shut down the VM
- `vagrant up` to turn on the VM
- `vagrant reload` apply .env settings like MEMORY, CPUS
- `./destory.sh` to destroy the VM and start from scratch

If you want to repeat from scratch for some reason, you can run `./destroy.sh` and retry `bootstrap.sh`.

## Packages covered by setup (host)

- vagrant
- virtualbox
- vscode
- git
- Windows Terminal (Windows)
- iterm2 (Mac)
- gnu-sed (Mac)

## Packages covered by bootstrap

- docker (installed by vagrant provision)
- docker-compose
- python3-pip
- git
- zsh
- oh-my-zsh
- vim-gtk (for vim-python3)
- dnsutils

## docker storage

Docker tend to use many small files especially for node.js

If the main storage has not enough inodes, docker can fail because of the disk space.
You can check that `df -h` has some free space but `df -hi` shows a low free space.

BTW, You can prune unused file by following docker command but it would rebuild required files soon.

```sh
docker system prune --volumes
```

This vgrantfile has additional space file of 40GB and it can be configured by `DOCKER_DISK_SIZE_GB=40`

## Details For Windows 10 users

<details>
  <summary>Click to expand!</summary>

### setup.ps1

> :warning: **Note that this script will disable WSL2(Hyper-V).**
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

### bootstrap.sh

Open Windows Terminal for Gitbash or just Git Bash

In linuxdev dir (this repo)

```bash
./bootstrap.sh
```

This will create virtualbox machine and bootup and config

### Map network drive from the machine

Virtualbox machine has IP of 192.168.99.123 by default
and it shares Projects directory so Host machine can see the files in it.

\\192.168.99.123\Projects

** Windows git global config should turn filemode off

</details>
    
## Configure .env

You can create .env to customize. The default values will be used if not exists.

### Name

```
NAME=awesome-name
```

This will rename the machine name in VirtualBox. run `vagrant reload` to apply when updated.

### Cpus and memory

```
CPUS=4
MEMORY=8192
```

This will adjust cpus and memory, run `vagrant reload` to apply when updated.

### Expand disk size :warning:

```
EXPAND_DISK_GB=10
```

It's using 60GB of disk image but it's dynamically allocated.
It's is great in most case but when the disk space is expanded, the VM performance will be deteriorated.

This will expand the disk during bootstrap.
And you will have some slowness on the VM for a while but would not be slow while using the VM afterwhile.

This should be setup before running bootstrap.
Or you can retry after removing `/dummy`


## Additional Goals

- Docker support for the host
  - create docker certificates
  - install docker tools for the host
    - docker-cli
    - docker-compose


## License

[MIT License](https://github.com/kennyhyun/linuxdev/blob/main/LICENSE)
