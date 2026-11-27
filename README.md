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

   **The group invite.** A buyer asking for an enchant you have gets a group invite, so you see on the map where they are; the buyer list shows their zone. Someone who declines isn't invited again from public chat for 5 minutes, but a whisper still gets an invite. If the group is full or you aren't the leader, they wait until a spot frees. 15 seconds after their enchant they're taken out of the group again. Only people EnchantPro invited are removed, never a friend who was already with you. Turn these off with the Invite and Kick switches, or `/ep invite` and `/ep kick`.
2. **Mats, if theirs.** The game needs the mats in *your* bags when you cast. With the buyer's mats, they trade you the mats first. The addon remembers what each buyer handed over.
3. **The item.** The buyer opens trade with the item in the bottom "Will not be traded" slot. Click the buyer's line when they're in range (the first one in range is highlighted) and the trade opens. It reads the item's slot and picks the enchant that fits; `<` and `>` switch between them.
4. **The trade dock.** A panel beside the trade window shows where the sale stands (Asked, Mats, Item, Cast, Paid), the mats in your bags, and the payment: what's in the trade against what you're owed.
5. **Cast and accept.** The dock's Cast button (or the one in the main window) casts the enchant onto the trade item; it glows when it's time to cast. The Accept button warns you if the item isn't enchanted yet or the trade is short.
6. **After the trade.** The sale goes into the ledger, and the buyer gets a thank-you whisper (or a `/say` line).

## The queue

Every buyer you can serve gets a number when they first ask (`#1`, `#2`…), and keeps it when they ask again. The Buyers tab lists the queue in that order, with how long each has waited; the mouse wheel scrolls it. The first reply tells a buyer their place ("You're #3 in the queue.") when someone is ahead of them.

One buyer is one order, even with several enchants: each one they name is added to the order (a second enchant for the same slot replaces the first, as a correction). The row lists them all and ticks each one off once cast; the dock picks the one that fits the item in the trade. The order is done when every enchant is.

Hover a buyer's line to see what they wrote (their last 5 lines, where and when) and which enchant each line was read as - handy when the addon picked up the wrong one.

Shift-right-click a line to **block** that character: they're taken off and never listed or answered again. `/ep block` lists who you blocked, `/ep block <name>` blocks by name, `/ep unblock <name>` undoes it.

An order stays until it's done, you right-click it away, or the buyer has been quiet for 2 hours. The queue is saved, so a `/reload`, a disconnect or a restart keeps it; each character has its own.

## Prices

Every enchant has two prices:

- **Fee:** what you charge when the buyer brings the mats. By default there's none: the enchant is free and any gold is a tip. Set a fee for every enchant with `/ep fee 20s`, or give only some enchants a fee of their own on the Enchants tab.
- **Full price:** what you charge with your own mats. Leave it blank and that enchant isn't offered with your mats.

If the buyer brings only some of the mats, you get the fee plus what your mats cost (capped at the full price). Mat costs come from `/ep matcost` or from Auctionator's scan.

Set prices, and tick which enchants the ad names, on the **Enchants** tab.

## Ledger

The Ledger tab shows today, the last 7 days and all time at a glance, a 7-day chart of income and tips, your best-selling enchants and who still owes you. It records:

- income, and how much of it was tips
- number of enchants, split into "their mats" and "my mats"
- what your own mats cost
- net profit for today, 7 days and all time
- buyers who paid short or not at all

## What still needs your click or key

The game reserves these actions for the player:

- casting
- opening and accepting the trade
- posting in public chat

On live Forever realms, addons can't send chat lines at all. Replies, the ad and the thank-you go into your chat box, and you press Enter to send them.

## Install

```
cd "World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/WoozChucky/EnchantPro.git
```

Open your Enchanting window once, so the addon learns your enchants. It loads only on characters with Enchanting.

## Use

Everything is in one window with tabs along the bottom: **Buyers**, **Enchants**, **Messages** and **Ledger**. Buyers show in their class colour, with the enchant's icon and a green dot when they're in range.

- `/ep` shows or hides the window; `/ep help` lists all commands.
- The **minimap button** shows how many buyers are waiting. Click it for the window, right-click to post the ad, drag it to move it. `/ep minimap` hides or shows it.
- `/ep compact` folds the window to one line (buyers waiting, in range, Post ad); again, or `+`, brings it back.
- A short **pop-up** with a sound tells you when a new buyer shows up.
- Key bindings are in Game Menu > Key Bindings > EnchantPro.

The window and the dock hold the Cast button, which the game locks in combat: showing, hiding or folding them waits until combat ends.

## Tests

```
pip install lupa
python tests/run_tests.py
```
