# valheim-server-installer

An interactive installer and management toolkit for one Valheim Dedicated Server on Ubuntu Server 22.04, 24.04, or 26.04 LTS (x86_64).

It installs the native Linux server through SteamCMD, runs it as a restricted system user, supports new or imported worlds, creates automatic backups, updates the game daily, and provides the `valheimctl` administration command.

## Requirements

- A fresh or existing x86_64 VPS running a supported Ubuntu Server LTS release.
- A normal SSH account with `sudo` access. Do not run the installer while logged in directly as `root`.
- Existing SSH/SFTP connectivity if you want to use WinSCP.
- Enough memory and disk space for Valheim and your world backups (at least 10 GiB free on `/opt`).

## Install

```bash
git clone https://github.com/daz-no/valheim-server-installer.git
cd valheim-server-installer
chmod +x install.sh
./install.sh
```

Do not pipe the installer directly into a privileged shell. Cloning it first lets you inspect exactly what will run.

The installer asks for the server display name, a hidden 5-64 character password, UDP base port, Steam or Crossplay networking, public visibility, and whether to create or import a world. Running it again repairs deployed scripts and updates the game while preserving existing configuration and worlds unless you explicitly change them.

## Start a new world

Choose **Start a new randomly generated world** and enter its name. Valheim creates it on the first successful server start.

The dedicated server cannot be given a seed directly. To use a particular seed, create the world in the Valheim game client, move it to local storage, and import it.

## Continue an existing world with WinSCP

Dedicated servers can only use local world files. In Valheim on the Windows PC:

1. Open **Manage Saves**.
2. Select the world and choose **Move to Local** if it is stored in Steam Cloud.
3. Close Valheim so the save is not changing.
4. Open `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local`.
5. Locate the matching pair, such as `My World.db` and `My World.fwl`.

During installation, choose **Import an existing local world through WinSCP**. The installer creates `~/valheim-world-upload`.

Connect WinSCP using the same hostname, SSH username, port, and SSH key/password used for the terminal. Select **SFTP**, upload both files to that directory, and return to the installer. If multiple complete pairs are present, it asks which one to use. Incomplete pairs and known backup filenames are ignored.

Uploaded originals remain in your home directory. After confirming the server loads the correct world, you may remove those copies yourself. To import another world later, run:

```bash
sudo valheimctl world import
```

The command safety-backs up the current state before changing the active world.

## Cloud firewall and connection mode

Steam-only mode requires inbound UDP access to the configured port and the next port. With the default, add this VPS security-group rule:

```text
Protocol: UDP
Ports:    2456-2457
Source:   0.0.0.0/0 and ::/0, or trusted player address ranges
```

If UFW is already active, the installer offers to add the matching local rule. It does not modify a provider firewall.

Crossplay uses the PlayFab relay and normally does not require an inbound port rule. It supports non-Steam platforms but cannot be tested using a loopback or local-only address. Inspect the server log for its join code with `sudo valheimctl logs --follow`.

These behaviors and Valheim's two-port range are documented in the [official dedicated-server guide](https://valheim.com/support/a-guide-to-dedicated-servers/).

## Manage the server

```bash
sudo valheimctl status
sudo valheimctl start
sudo valheimctl stop
sudo valheimctl restart
sudo valheimctl logs
sudo valheimctl logs --follow
sudo valheimctl info
sudo valheimctl configure
```

World commands:

```bash
sudo valheimctl world list
sudo valheimctl world new "New World"
sudo valheimctl world select "Existing World"
sudo valheimctl world import
```

Access-list commands use the case-sensitive Platform User ID shown by Valheim's F2 panel or server log, such as `Steam_123456789`:

```bash
sudo valheimctl access admin add Steam_123456789
sudo valheimctl access admin list
sudo valheimctl access ban add Steam_123456789
sudo valheimctl access permit add Steam_123456789
sudo valheimctl access admin remove Steam_123456789
```

Adding anyone to the permitted list prevents everyone not on that list from joining.

## Backups, updates, and restore

At `04:00` server-local time each day, maintenance gracefully stops Valheim, creates a cold backup, runs SteamCMD update validation, and restarts the service. The newest 14 archives are retained. Valheim's rolling world backups also remain enabled.

```bash
sudo valheimctl schedule 03:30
sudo valheimctl backup
sudo valheimctl update
sudo valheimctl backup list
sudo valheimctl restore
```

To download an archive through WinSCP, run `sudo valheimctl backup export`, choose an archive, and download it from `~/valheim-backup-downloads`. Archives include the server password, so store exported copies securely.

A restore verifies archive paths and its checksum, creates a pre-restore safety backup, and rolls back if restoration fails.

## Files and security

| Path | Purpose |
| --- | --- |
| `/opt/valheim/steamcmd` | SteamCMD runtime |
| `/opt/valheim/server` | Valheim server binaries |
| `/var/lib/valheim/worlds_local` | Active and inactive local worlds |
| `/etc/valheim/server.conf` | Root-managed server configuration |
| `/var/backups/valheim` | Root-only backup archives |
| `~/valheim-world-upload` | WinSCP import staging |
| `~/valheim-backup-downloads` | Exported archives |

Valheim runs as the non-login `valheim` system user. Configuration is readable only by root and the service group. Because Valheim requires its password as a process argument, VPS administrators may still be able to inspect it; do not reuse a personal password.

## Troubleshooting

```bash
sudo valheimctl status
sudo valheimctl logs
sudo systemctl status valheim-maintenance.timer --no-pager
sudo journalctl -u valheim-maintenance.service -n 100 --no-pager
```

Common connection problems include a missing cloud security-group rule in Steam mode, opening only one UDP port, selecting the wrong backend in the client, or trying to use a local address with Crossplay. If installation stops, correct the displayed problem and run `./install.sh` again; managed data is preserved by default.

## Tests

```bash
bash tests/run.sh
```

## v1 scope

This release manages one native, unmodded instance. Multiple instances, mods, Docker, cloud backup providers, a web dashboard, and automatic provider-firewall changes are intentionally out of scope.
