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

It's okay to repeat this bootstrap script.

### After finished bootstrap

Copy and paste ssh public key to use in Github and so on

Now you can ssh into Linux dev env

```bash
ssh linuxdev
```

Run `init_dotfiles.sh` to continue setting up dotfiles
In ssh, run `/vagrant/init_dotfiles.sh` 

It installs basic devtools from external [dotfiles project](https://github.com/kennyhyun/dotfiles)

You can override repo by `DOTFILE_REPO=git@github.com:kennyhyun/dotfiles.git`

### Commands

- `vagrant halt` to shut down the VM
- `vagrant up` to turn on the VM
- `./destory.sh` to start from scratch

If you want to repeat from scratch for some reason, you can run `./destroy.sh` and retry `bootstrap.sh`.


### Details For Windows 10 users

#### setup.ps1

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

##### bootstrap.sh

Open Windows Terminal for Gitbash or just Git Bash

In linuxdev dir (this repo)

```bash
./bootstrap.sh
```

This will create virtualbox machine and bootup and config

##### Map network drive from the machine

Virtualbox machine has IP of 192.168.99.123 by default
and it shares Projects directory so Host machine can see the files in it.

\\192.168.99.123\Projects

** Windows git global config should turn filemode off



## Configure .env

You can create .env to customize. The default values will be used if not exists.

### Name

```
NAME=awesome-name
```

This will rename the machine name in VirtualBox. run `vagrant reload` to apply when udpated.

### Cpus and memory

```
CPUS=4
MEMORY=8192
```

This will adjust cpus and memory, run `vagrant reload` to apply when udpated.

### Expand disk size :warning:

```
EXPAND_DISK_GB=10
```

It's using 60GB of disk image but it's dynamically allocated.
It's is great in most case but when the disk space is expanded, the VM performance will be deteriorated.

This will expand the disk during bootstrap along creating swapfile.
And you will have some slowness on the VM for a while but would not be slow while using the VM afterwhile.

This should be setup before running bootstrap.
Or you can retry after removing /swapfile


## Additional Goals

- Docker support for the host
  - create docker certificates
  - install docker tools for the host
    - docker-cli
    - docker-compose


## License

[MIT License](https://github.com/kennyhyun/linuxdev/blob/main/LICENSE)
