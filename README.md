# Linuxdev

Boot up Linux development env using Vagrant

|  | Docker Desktop  | Linuxdev with Vagrant |
|--|------|------|
|Docker hub account	|<sub>signin is required if you want to stop checking updates</sub>	|<sub>✅**login to Docker hub is not necessary**</sub>|
|Control over the Docker Engine Version	|<sub>Should use latest above v3, unless the user ignore the updates</sub>|<sub>✅**have the controll for docker-ce (community edition)**</sub>|
|Licensing	|<sub>free for small business and personal, but auto-checking-update</sub>|<sub>✅**free of charge (w/o VB extension pack)**</sub>|
|Network setup	|<sub>Host network	</sub>|<sub>✅**Can Choose <br>. Bridge(host) <br>. NAT + Host-only**</sub>|
|Performance	|<sub>. Hyper-v VM; might be slightly better but it likely consumes more memory</sub>|<sub>. Virtualbox VM; not so bad<br>. Has alternatives (Hyper-v/VMWare/Virtualbox)</sub>|
|Environment	|<sub>Slightly different environment between<br>. Windows WSL2 (Custom distro integration required for Docker host access)<br>. Windows VM (w/o Docker host acess)<br>. Mac VM (w/o Docker host acess)</sub>|<sub>✅**Common Linux environment available in Mac/Windows<br>. Full Linux VM will be provided as a Docker host<br>  (Files can be shared natively in Linux host)<br>. Docker engine can be also accessed from the host OS<br>  (docker and docker-compose client installation required)**</sub>|
|Installation	|<sub>Installer provided</sub>|<sub>Install scripts provided</sub>|
|Starting Docker	|<sub>**Autostart configurable**</sub>|<sub>Startup script is provided both for Windows and Mac</sub>|
|Clients	|<sub>Provided along with the Docker Desktop installer</sub>|<sub>Install scripts provided</sub>|
|Config	|<sub>✅**Configurable in GUI**</sub>|<sub>Configurable in script</sub>|
|Docker storage	|<sub>Configurable size</sub>|<sub>✅**Configurable 2k block size with a lot of inodes**</sub>|
|Logs/status	|<sub>✅**GUI provided**</sub>|<sub>Only available in CLI</sub>|
|Limiting memory usuage	|<sub>.wslconfig file for WSL2/GUI for VM</sub>|<sub>.env file/VirtualBox GUI</sub>|


## ⚠ Note for Windows VBS (Virtualization-based security or Device Guard)

**Some** recent windows update enables VBS and it will turn on hyper-v
and that would make Vrtualbox slow and unstable.

If `systeminfo` command shows following at the bottom, it's good to use Virtualbox.

```
Hyper-V Requirements:      VM Monitor Mode Extensions: Yes
                           Virtualization Enabled In Firmware: Yes
                           Second Level Address Translation: Yes
                           Data Execution Prevention Available: Yes
```                        

Pease follow [he issue](https://github.com/kennyhyun/linuxdev/issues/71) for further guidance.

## Why?

Docker is necessary for developing nowadays. But if you are not using Linux as the OS, it requires VM for Docker engine.

I was using Linux in Virtualbox for many years and found that was quite nice and had no problem for using docker in it. And personally satisfied with the performance of docker in VM
In the other hand, Docker Desktop, I found couple of issue with using Docker Desktop in Windows recently.

<details>
<summary>What I didn't like about WSL/Docker Desktop</summary>
    
- Memory usage is keep growing upto VM memory limitation
- some file was missing for binding into docker
- Additional settings to ssh in to the linux
- ssh connection env was a bit different (not sure) when used in terminal
- X client was blocked by Windows Firewall
- not sure what it was but felt heavy

</details>

### Some known Docker Desktop for Windows issue

- Watching files in the host is not working
- Hyper-v is not returning unused memory frequently so the host can be struggling with memory.

So it's generally recommended to use WSL2 Ubunu but I would rather use VM

### Linuxdev with Vagrant (VirtualBox)

- Virtualbox seems to be able to run many containers more stable and does not apply much pressure to the host memory. (compared to WSL2)
- Generally there are less issues in developing in Linux than Windows (Same reason to use WSL2)
- Full configurable linux host (docker)
- USB ports can be used directly in VM (Note: USB3 in VB is available in the extension pack, which is free for only personal users)

### Also for Mac Users

Not only for the Windows users, there would be some advantage for Mac users as well

- Easily backup/cleanup VM/dev env
- The dev env is a sandbox
- A reference environment for Linux env
- Run linux GUI apps using X server and tunneling
- Docker is running Linux VM already, why not?
- Multiple network interfaces available

And if you are familiar with the Linux command line, using Linux makes more senses than using Docker Desktop.

- Share VM when you need to bootcamp to windows
- Access to docker host
- Unlimited access to host(Linux VM) root directory
- Faster host(Linux VM) volume sharing
- Free

### Performance comparison

For comparison, I tried one of my project which builds multiple docker images with node.js and filling up 20GB of docker storage.

Building includes installing node packages and webpack.
Docker build kit was used for cache mounting.

|Env|Build Time|Note|
|--|--|--|
|Linuxdev (Windows host)<br>6GB, i7 4 cores| 24m 12s | |
|WSL2 (Docker Descktop)<br>16GB, i7 6 cores (no .wslconfig) |19m 18s| spent up to 13GB|
|WSL2 (Docker Descktop)<br>8GB, i7 6 cores (with .wslconfig)| 18m 22s||
|Linuxdev (Windows host)<br>8GB , i7 6 cores| ✅ **14m 39s**||
|Mac OSX (Docker Descktop)<br>8GB, i7 6 cores| 19m 37s|First build failed after 1 hour|
|Linuxdev (Windows host)<br>8GB , i7 4 cores| 21m 13s||

This was just an instance of the build. Just to let you know.
As you noticed, Linuxdev was the best in some situation.

## Setting up the Linuxdev environment

### ⚠ Note for Windows users
The script will disable Hyper-v (WSL2) and replace with VM and you can also use Docker from the host OS

### Running scripts

1. Unzip or git clone this repo
    - https://github.com/kennyhyun/linuxdev/archive/refs/heads/main.zip
1. Run setup scripts
    - Windows
        1. Install host dependencies and dev tools
            - Open powershell as Admin and run
              - `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`: enables ps1 for this powersell process
              - `setup.ps1`
            - This might require rebooting.
        1. Bootup vagrant with provision
            - Open terminal (git bash) and run `bootstrap.sh`
    - Mac
        1. Install host dependencies and dev tools
            - Open teminal and run `setup.sh`
        1. Bootup vagrant with provision
            - continue to run `bootstrap.sh`
1. Wait until bootstrap.sh does
    - input username to use in the VM
    - Install Debian Linux 10.10
    - Install Docker v20.10.8 (configurable in config/env_var.sh; remove VERSION if you want the latest)
    - Install docker-compose (v1.29.2; configurable in .env `__VM__COMPOSE_VERSION`)
    - Create a user with UID 1000 and sudoer
    - ohmyzsh
    - expose samba share, `Projects`
    - generate id_rsa key and show public key
    - add ssh config for linuxdev
    - generate docker certificates and set bash variables

It's okay to repeat this bootstrap script if something went wrong.

### After finished bootstraping

Copy and paste ssh public key to use in Github and where ever it's required.

Now you can ssh into Linux dev env

```bash
ssh linuxdev
```

and you can also run any linux commands from the host terminal

```bash
ssh linuxdev -t echo hello from VM
```

For Windows Terminal, there is also a profile generated for the machine.

An additional external configuration [dotfiles project like this](https://github.com/kennyhyun/dotfiles) can be added 

If DOTFILES_REPO has been defined in `.env`, it clones the repo to ~/dotfiles and try to run

- bootstrap*
- init*
- install*
- setup*

any of files which is executable.

## Demo

`setup.ps1` (Windows Powershell script; Use setup.sh for Mac)

[![asciicast](https://asciinema.org/a/IqGHfToxLcfSwSJRoBIHZBoWY.svg)](https://asciinema.org/a/IqGHfToxLcfSwSJRoBIHZBoWY)

`bootstrap.sh` (Mac; You can also use it in Git bash in Windows Terminal)

[![asciicast](https://asciinema.org/a/o7HNUExImgO6gCKjlUTczwK7G.svg)](https://asciinema.org/a/o7HNUExImgO6gCKjlUTczwK7G)


## Packages managed by Linuxdev

### Packages covered by setup (host)

- vagrant
- virtualbox
- vscode
- git
- Windows Terminal (Windows)
- iterm2 (Mac)
- gnu-sed (Mac)
- and so on...

### Packages covered by bootstrap (VM)

- docker (installed by vagrant provision)
- docker-compose
- python3-pip
- git
- zsh
- oh-my-zsh
- vim-gtk (for vim-python3)
- dnsutils
- and so on...

## [Tips](./docs/tips.md)

## [Configuring VM](./docs/configuring-vm.md)

## Installing and using docker clients

This vm provides docker connection in `2376` port.
If you have docker client and set the env vars you can use docker from the host like Docker Desktop.

You can also install docker and docker-compose by running install-docker-clients script.

`.bashrc` or `.zshrc` has DOCKER_HOST and required variables for Mac/Git-bash and `docker_env.bat` will set variables in the command terminal in Windows.

Bootstrap installes the required variables automaticaly so you can use docker straightaway.

## Additional Goals

- Share virtualbox env across Bootcamp
- Provide recommended fonts with Powerline patch

## License

[MIT License](https://github.com/kennyhyun/linuxdev/blob/main/LICENSE)
