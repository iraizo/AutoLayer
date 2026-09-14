# AutoLayer - WoW Layering Community Addon

AutoLayer automates layer-switching invites for World of Warcraft Classic Era and Burning Crusade Classic.

## Supported Clients

- **Classic Era**: Interfaces `11508` and `11509`
- **Burning Crusade Classic**: Interface `20506`
- Client-specific API and protocol compatibility
- Optional zone checks for BCC layer invites

## Features

- Configurable invite triggers, blacklist, ignored prefixes, and channel filters
- Whisper notifications with customizable templates
- Layer Hopper GUI and `/autolayer req [layers]`
- Group-capacity checks, including pending invites
- Leader and raid-assistant permission checks
- Manual auto-kick queue for offline or oldest group members
- Optional party sounds and system-message suppression
- Optional loot-method and threshold overrides

## Slash Commands

- `/autolayer`: Open settings
- `/autolayer status`: Show addon, layer, zone/segment, channel, and queue status
- `/autolayer stats`: Show lifetime and session statistics
- `/autolayer req [layers]`: Request specific layers, or all layers except the current one
