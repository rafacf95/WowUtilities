# WowUtilities

Modular all-in-one utilities for **WoW Forever**. Small quality-of-life features in one addon
instead of many, and each one can be turned on or off separately.

> **WoW Forever only** (Interface 16001). It is not made for Retail, Classic Era or other clients.

*Versão em português abaixo.*

## Features

### Tooltips
- Player names (with title) in **class color**, and the class/specialization line too.
- **Faction** line colored: Horde in red, Alliance in blue.
- **Border** on NPC tooltips: gold for elites and world bosses, silver for rares. Both colors can be changed.

### Flight times
- **Duration on the flight map tooltip**, learned from your own flights. A `~` marks an estimate
  (built from known legs of the route or from the distance).
- **Flight bar** during the flight, like a cast bar, with the time left. Texture, border, colors
  (or your class color), size, scale, text size and fill direction are all configurable.

### Vendors
- **Gold summary** when you close a vendor: sold, bought, repairs and the net result.
- Optional message after each transaction.

### Appearance collection
- **Armor type filter** (cloth, leather, mail, plate, cosmetic) on the Items tab of the
  Appearances window.

### Trinket selector
- An on-screen button for each trinket slot. Click one to see the trinkets in your bags, sorted by
  item level, and click a trinket to equip it (out of combat).
- Shows cooldowns and item levels. Vertical or horizontal layout; dims or hides during combat.

### Item level and enchants
- **Item level** on equipment in the default bags, on the character window and on the Inspect
  window, in item quality color or a fixed color, on the corner you choose.
- **Enchants** on the character window and on the Inspect window: shows which items are enchanted
  (full, abbreviated or value-only name) and which are missing an enchant. Rings count only for
  Enchanters, if you want (on the Inspect window, a separate option).

## Positioning

- With the optional **LibEditMode** addon,
  the flight bar and the trinket selector are moved in the game's **Edit Mode**, with a position
  per layout and their options in the Edit Mode panel. The flight bar can also be **anchored** to
  other frames (player frame, action bars...) and match their width.
- Without it, unlock and drag them from the settings window.

**LibSharedMedia-3.0** is optional too:
when installed, its bar textures appear in the flight bar options.

## Commands

| Command | What it does |
|---|---|
| `/wu` or `/wowutilities` | Opens the settings window |
| `/wu taxi` | Lists the recorded flight times |
| `/wu taxi clear` | Deletes the recorded flight times (asks for confirmation) |
| `/wu debug <name>` | Diagnostic report to copy into a bug report: `bags`, `character`, `enchants`, `editmode`, `anchors`, `trinkets`, `wardrobe`, or a unit such as `target` |

## Installation

1. Download the latest zip from [Releases](../../releases) (CurseForge coming soon).
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns`, so that you get
   `AddOns\WowUtilities\WowUtilities.toc`.
3. Restart the game or type `/reload`.

Languages: English and Português (Brasil). Other clients show English.

## Bug reports and suggestions

Open an [issue](../../issues). For problems with bags, the character window, enchants, the
appearance collection, trinkets or Edit Mode, please attach the output of the matching
`/wu debug` command. Pull requests are not accepted (see the license).

## License

Free to download and use, with all rights reserved. You may use it in your UI and in unmodified UI
packs, and modify it for your own private use; you may not redistribute, reupload or rename it.
See [LICENSE](LICENSE) for the full terms.

---

## Português

Utilidades para o **WoW Forever** reunidas num só addon, cada uma ligável e desligável à parte:

- **Tooltips:** nome (com título) e classe na cor da classe, facção colorida e borda dourada
  (elites e chefes de mundo) ou prateada (raros) nas tooltips de NPCs.
- **Voos:** duração do voo na tooltip do mapa, aprendida com os seus voos (`~` indica estimativa),
  e uma barra de voo configurável com o tempo restante.
- **Vendedores:** resumo de gold ao fechar (vendido, comprado, reparo e saldo).
- **Coleção de aparências:** filtro por tipo de armadura na aba Itens.
- **Seletor de berloques:** botões na tela para trocar de berloque com um clique, fora de combate.
- **Nível de item e encantamentos:** nas bolsas padrão, na janela de personagem e na janela de inspeção.

Com o addon opcional **LibEditMode**, a barra de voo e o seletor de berloques são posicionados
pelo **Modo de Edição** do jogo (por layout, com âncora em outras janelas). Sem ele, destrave e
arraste pela janela de configuração.

**Comandos:** `/wu` abre a configuração; `/wu taxi` lista os tempos de voo; `/wu taxi clear`
apaga; `/wu debug <nome>` gera um relatório para anexar a relatos de bug.

**Instalação:** baixe o zip em [Releases](../../releases) e extraia em
`World of Warcraft\_forever_\Interface\AddOns`. Bugs e sugestões: abra uma [issue](../../issues)
(não aceitamos pull requests). Licença: uso livre, todos os direitos reservados; veja o
[LICENSE](LICENSE).
