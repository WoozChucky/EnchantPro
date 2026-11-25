# EnchantPro

A WoW Forever addon for enchanters who sell enchants. It automates as much of the job as the game's API allows. It is a sister addon to [PortalPro](https://github.com/WoozChucky/PortalPro).

## How a sale works

1. **The buyer asks.** The addon finds them in Trade, General, LFG, say, yell or whispers ("LF enchanter +7 stam bracer", "WTB crusader", "can you do agi boots?"). It works out which of your enchants they mean and answers with the price and mats. A linked enchant counts too, matched exactly by its spell ID.

   Enchanters advertising are left out. A line counts as a seller's when it has any of these:
   - WTS or LFW
   - an [Enchanting] profession link
   - three or more linked enchants
   - "customers", "tips appreciated" or "your mats"

   Their chat lines are then skipped for an hour; whispers from them still count. Links to recipe items ([Formula: ...]) are ignored.
2. **Mats, if theirs.** The game needs the mats in *your* bags when you cast. With the buyer's mats, they trade you the mats first. The addon remembers what each buyer handed over.
3. **The item.** The buyer opens trade with the item in the bottom "Will not be traded" slot. The addon opens trade by itself when a buyer comes in range. It reads the item's slot and picks the enchant that fits; `<` and `>` switch between them.
4. **Payment check.** It compares what you're owed with the gold in the trade, and the line above the trade window shows PAID or how much is missing.
5. **Cast and accept.** The Cast button casts the enchant onto the trade item. The Accept button warns you if the item isn't enchanted yet or the trade is short.
6. **After the trade.** The sale goes into the ledger, and the buyer gets a thank-you whisper (or a `/say` line).

## Prices

Every enchant has two prices:

- **Fee:** what you charge when the buyer brings the mats. There's one default fee, and each enchant can have its own.
- **Full price:** what you charge with your own mats. Leave it blank and that enchant isn't offered with your mats.

If the buyer brings only some of the mats, you get the fee plus what your mats cost (capped at the full price). Mat costs come from `/ep matcost` or from Auctionator's scan.

Set prices, and tick which enchants the ad names, in the **Enchants** window.

## Ledger

The ledger records:

- income, and how much of it was tips
- number of enchants, split into "their mats" and "my mats"
- what your own mats cost
- net profit for today, 7 days and all time
- buyers who paid short or not at all

## What still needs your click or key

The game reserves these actions for the player:

- casting
- accepting the trade
- posting in public chat

On live Forever realms, addons can't send chat lines at all. Replies, the ad and the thank-you go into your chat box, and you press Enter to send them.

## Install

```
cd "World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/WoozChucky/EnchantPro.git
```

Open your Enchanting window once, so the addon learns your enchants. It loads only on characters with Enchanting.

## Use

Type `/ep` to show or hide the panel and `/ep help` for all commands. Key bindings are in Game Menu > Key Bindings > EnchantPro.

## Tests

```
pip install lupa
python tests/run_tests.py
```
