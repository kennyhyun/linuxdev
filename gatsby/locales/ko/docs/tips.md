<!---
title: Tips
date: 2021-09-26
--->

# 팁

## 유용한 명령

- `vagrant halt` 로 VM을 종료합니다
- `vagrant up` 으로 VM을 시작합니다
- `vagrant reload` 로 MEMORY, CPUS와 같은 .env 세팅을 적용하고 **재부팅** 합니다
- `./destory.sh` 로 VM을 파기하고 생성전의 상태로 돌아갑니다.

여러가지 이유로 처음부터 시작하고 싶다면, `./destroy.sh` 한 후 다시 `bootstrap.sh` 명령을 실행하면 됩니다.

## 도커

VM안에서 도커가 이용가능하고 VM을 위해 작동중인 samba 컨테이너를 확인할 수 있습니다.

호스트쪽에서도 도커를 사용할 수 있습니다.

도커 실행파일이 설치되어있지 않으면 install-docker-clients 스크립트를 이용해 도커 명령어를 설치할 수 있습니다

[Vagrant 매니저](https://www.vagrantmanager.com/) 도 사용하시면 좋습니다.


## VM으로부터 네트웍 드라이브 매핑

Virtualbox 머신은 디폴트로 IP어드레스 192.168.99.123 가 설정됩니다.
그리고 유저 홈의 Projects 디렉토리를 공유하고 있습니다. 호스트 머신은 VM내의 Projects 디렉토리를 매핑할 수 있습니다.

```
\\192.168.99.123\Projects
```

** 윈도우쪽에 설치된 git을 사용하는 경우는 global config의 filemode를 off로 설정하여야 합니다.

## Setup 명령 파라메터

```powershell
.\setup.ps1 -nodevtools
```

또는

```bash
./setup.sh --no-devtools
```

는 git(for Mac), vscode, terminal 등의 설치를 건너뜁니다.

`--no-{vscode,git,vagrant,virtualbox,...}` 옵션도 사용 할 수 있습니다

** 윈도우에서 git은 gitbash 때문에 필수입니다.

### basic os setting

`-withosconfig` 로 다음과 같이 필수 레지스트리를 수정 합니다

- Secure Desktop (UAC Dimming) 비활성
- active hour 설정 (오전 8시 부터 오전 2시)
- 숨김파일 및 확장자 표시
- Windows Update 비활성

You can also run separately by `scripts/basic-config.ps1`

## 도커 저장소

도커는 특히 node.js 프로젝트를 사용하는 경우 많은 작은 파일을 사용하게 됩니다.

만약 주 디스크 용량이 inode 갯수가 부족한 경우는 도커 명령이 실패할 수 있습니다.
만약 그러한 상황일 경우 `df -h`명령으로는 공간이 좀 남아있지만, `df -hi`명령으로는 여유가 없는 것을 확인할 수 있을 것입니다.

그럴 때에 보통 도커 커맨드로 사용하지 않는 파일들을 지워서 공간을 확보할 수 있지만 곳 다시 용량부족으로 문제가 될 수 있습니다.

```sh
docker system prune --volumes
```

본 Vagrantfile은 `DOCKER_DISK_SIZE_GB=40` 설정으로 40GB용량의 도커만의 고유 디스크 저장소를 확보 할 수 있습니다.

## 윈도우10 사용자를 위한 추가 설명

### setup.ps1

> :warning: **본 스크립트는 WSL2(Hyper-V)를 비활성 합니다.**
>
> 실행전에 WSL쪽에서 필요한 파일들을 백업하세요. 도커는 VM을 통해서 다시 이용가능합니다.

윈도우 메뉴버튼을 오른클릭 하여 윈도우 파워쉘 (관리자)를 클릭합니다.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

본 리포지터리의 폴더 (linuxdev)의 셋업 스크립트를 실행합니다.

```powershell
\Users\xxx\linuxdev\setup.ps1
```

** 셋업 스크립트를 다시 실행하게 되면 최신버전을 확인하고 새 버전이 있으면 설치합니다.

### bootstrap.sh

Windows Terminal의 Gitbash를 열거나 Git Bash창을 엽니다.

linuxdev 디렉토리 (본 리포지터리) 에서

```bash
./bootstrap.sh
```

위 명령은 virtualbox 머신을 생성하고 부팅시키고 자동 설정을 수행합니다.

