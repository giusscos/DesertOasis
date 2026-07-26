# Game Center Configuration Reference

Use this file as the source of truth when configuring Game Center in App Store Connect and Xcode.

---

## Achievements

Total points: **775 / 1000**

| # | Reference Name | ID (App Store Connect) | Display Title | Points | Hidden |
|---|---|---|---|---|---|
| 1 | First Drop | `first_drop` | First Drop | 25 | No |
| 2 | Glimmer Found | `first_oasis` | Glimmer Found | 25 | No |
| 3 | Beyond the Horizon | `first_remote` | Beyond the Horizon | 50 | No |
| 4 | Steady Hands | `five_deliveries` | Steady Hands | 50 | No |
| 5 | Trail Companion | `animal_helper` | Trail Companion | 50 | No |
| 6 | Open the Route | `merchant_trade` | Open the Route | 50 | No |
| 7 | Through the Storm | `sandstorm_survived` | Through the Storm | 75 | No |
| 8 | Ancient Water | `landmark_found` | Ancient Water | 75 | No |
| 9 | Living Oasis | `oasis_lush` | Living Oasis | 75 | No |
| 10 | Kindness of the Dunes | `five_wanderers` | Kindness of the Dunes | 100 | No |
| 11 | Keeper's Memory | `all_diary` | Keeper's Memory | 100 | No |
| 12 | Flourishing | `oasis_flourishing` | Flourishing | 100 | No |

### Achievement Descriptions (localized copy)

> These are the player-facing descriptions. Paste them into the **Earned Description** field. Use the same text for **Pre-Earned Description** unless you want to keep the goal vague.

---

**1 · First Drop** (`first_drop`)
- **Earned:** You tipped the first bucket into the barrel. The desert remembers every drop.
- **Pre-Earned:** Deliver water to a camp barrel for the first time.

---

**2 · Glimmer Found** (`first_oasis`)
- **Earned:** You found water where there was none. Light follows those who look.
- **Pre-Earned:** Discover your first oasis out in the dunes.

---

**3 · Beyond the Horizon** (`first_remote`)
- **Earned:** The desert is wider than one camp. You have walked far enough to know it.
- **Pre-Earned:** Find another camp out in the desert.

---

**4 · Steady Hands** (`five_deliveries`)
- **Earned:** Five barrels filled, five mornings made easier. You carry well.
- **Pre-Earned:** Make five water deliveries to a camp barrel.

---

**5 · Trail Companion** (`animal_helper`)
- **Earned:** A camel or goat walks beside you now. The desert is less lonely.
- **Pre-Earned:** Call an animal to follow you with the magic stick.

---

**6 · Open the Route** (`merchant_trade`)
- **Earned:** Beads exchanged, a road opened. Trade keeps the oasis alive.
- **Pre-Earned:** Buy something from the merchant.

---

**7 · Through the Storm** (`sandstorm_survived`)
- **Earned:** The storm took everything visible and left you standing. You waited it out.
- **Pre-Earned:** Wait out a sandstorm in the desert.

---

**8 · Ancient Water** (`landmark_found`)
- **Earned:** Stone bowls still catch dew. Pilgrims left beads here long before you arrived.
- **Pre-Earned:** Discover a landmark spring hidden in the dunes.

---

**9 · Living Oasis** (`oasis_lush`)
- **Earned:** Roots have taken hold. The camp oasis breathes on its own now.
- **Pre-Earned:** Grow a camp oasis to the lush stage.

---

**10 · Kindness of the Dunes** (`five_wanderers`)
- **Earned:** Five weary travellers walked away with water. The desert repays kindness slowly but surely.
- **Pre-Earned:** Help five weary travellers crossing the desert.

---

**11 · Keeper's Memory** (`all_diary`)
- **Earned:** Every page recovered. The keeper's story is whole again.
- **Pre-Earned:** Collect every diary page in the desert.

---

**12 · Flourishing** (`oasis_flourishing`)
- **Earned:** The oasis is flourishing. What was dust is now a gathering place.
- **Pre-Earned:** Push a camp oasis into the flourishing stage of life.

---

## Leaderboards

All leaderboards use **Integer** score type, **Descending** order (higher is better), and no score range limit.

| # | Reference Name | ID | Display Name | Score Label |
|---|---|---|---|---|
| 1 | Water Deliveries | `oasis_keeper.deliveries` | Water Deliveries | Buckets Delivered |
| 2 | Oases Discovered | `oasis_keeper.oases` | Oases Discovered | Oases Found |
| 3 | Wanderers Helped | `oasis_keeper.wanderers` | Wanderers Helped | Travellers Helped |

### Leaderboard Descriptions

**1 · Water Deliveries** (`oasis_keeper.deliveries`)
- How many buckets of water you have delivered to camp barrels across all sessions.

**2 · Oases Discovered** (`oasis_keeper.oases`)
- How many oases you have found hidden in the dunes.

**3 · Wanderers Helped** (`oasis_keeper.wanderers`)
- How many weary travellers you have given water to out in the desert.

---

## Image Assets

All images are **512 × 512 px RGB PNG** (no transparency), in the same voxel / sunset style as the app icon.

**Folder:** `DesertOasis/Assets/GameCenter/`

### Achievement images

Upload the coloured file as the **earned** image and the `_locked` file as the **locked** image.

| ID | Earned | Locked |
|---|---|---|
| `first_drop` | `Achievements/first_drop.png` | `Achievements/first_drop_locked.png` |
| `first_oasis` | `Achievements/first_oasis.png` | `Achievements/first_oasis_locked.png` |
| `first_remote` | `Achievements/first_remote.png` | `Achievements/first_remote_locked.png` |
| `five_deliveries` | `Achievements/five_deliveries.png` | `Achievements/five_deliveries_locked.png` |
| `animal_helper` | `Achievements/animal_helper.png` | `Achievements/animal_helper_locked.png` |
| `merchant_trade` | `Achievements/merchant_trade.png` | `Achievements/merchant_trade_locked.png` |
| `sandstorm_survived` | `Achievements/sandstorm_survived.png` | `Achievements/sandstorm_survived_locked.png` |
| `landmark_found` | `Achievements/landmark_found.png` | `Achievements/landmark_found_locked.png` |
| `oasis_lush` | `Achievements/oasis_lush.png` | `Achievements/oasis_lush_locked.png` |
| `five_wanderers` | `Achievements/five_wanderers.png` | `Achievements/five_wanderers_locked.png` |
| `all_diary` | `Achievements/all_diary.png` | `Achievements/all_diary_locked.png` |
| `oasis_flourishing` | `Achievements/oasis_flourishing.png` | `Achievements/oasis_flourishing_locked.png` |

### Leaderboard images

| ID | Image |
|---|---|
| `oasis_keeper.deliveries` | `Leaderboards/oasis_keeper.deliveries.png` |
| `oasis_keeper.oases` | `Leaderboards/oasis_keeper.oases.png` |
| `oasis_keeper.wanderers` | `Leaderboards/oasis_keeper.wanderers.png` |

---

## Notes for App Store Connect

- **Achievement images:** 512 × 512 px PNG, no transparency. Use the locked image for locked state and a coloured version for earned.
- **Leaderboard images:** 512 × 512 px PNG. One image per leaderboard.
- After adding all achievements and leaderboards, click **Sync** in Xcode (Product → Game Center → Sync) to pull the configuration into the local `.gameconfig` file and enable local testing via the Game Progress Manager.
- Achievement IDs in this file match exactly what is used in code (`AchievementManager.catalog` and `GameCenterManager.Leaderboard`). Do not rename them.
