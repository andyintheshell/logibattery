# Battery-life model: Logitech MX Ergo (500 mAh Li-Po) vs ERGO K860 (2× AAA)

Research companion for `mxbattery`. Every figure is tagged:

- **[official]** — manufacturer datasheet/product copy, manufacturer reference text, or patent/whitepaper
- **[community]** — owner logs, reviews, forum reports
- **[derived]** — arithmetic performed here from tagged inputs
- **[not found]** — searched for and genuinely not published/found (stated explicitly, never estimated)

Scope: separating chemistry self-discharge, active/idle device draw, usage assumptions,
power-switch behavior, and real-world data for the two devices the script models.

---

## 0. Bottom line

| | MX Ergo / MX Ergo S | ERGO K860 |
|---|---|---|
| Battery | 500 mAh Li-Po, built-in, Micro-USB [official] | 2× AAA alkaline [official] |
| Official runtime | "up to 4 months" per charge [official] | "Up to 24 months" per set [official] |
| Implied calendar-average draw | ≈ **171 µA** [derived] | ≈ **57–68 µA** [derived, 1,000–1,200 mAh] |
| Self-discharge + protection (effective) | ≈ **27–34 µA** (1–2%/mo + 3%/mo protection) [derived from official] | ≈ **3–4 µA** (2–3%/yr) [derived from official] |
| Self-discharge share of budget | **16–20%** [derived] | **4–6%** [derived] |
| Dominant drain | radio + MCU wakeups + sensor | radio + scan engine |
| Owners observe | 2 wk (heavy) … ~2 mo (typical) … 3–4 mo (light) [community] | ~1 yr typical; still "full" at 7 mo of 8 h/day [community] |
| Aging | real capacity fade; replacement cell sold (iFixit 533-000121); 3+ yr service reported [community] | N/A (cells replaced); leakage risk if stored powered-off for months [official Duracell] |

---

## 1. Chemistry: how the cells behave while idle

### 1.1 Li-Po (MX Ergo, 500 mAh)

- **Rate:** "Li-ion self-discharges about 5 percent in the first 24 hours and then loses
  1–2 percent per month; the protection circuit adds another 3 percent per month." [official ref]
  https://batteryuniversity.com/article/bu-802b-what-does-elevated-self-discharge-do
- **Vendor catalog:** "Self-discharge is less than 2% per month." [official vendor]
  https://www.powerstream.com/li-pol.htm
- **Temperature/SOC detail (2026 knowledge base):** 50% SOC ≈ 1–2%/mo at 25 °C; 100% SOC ≈
  2–3%/mo at 25 °C and 5–6%/mo at 40 °C. [secondary institutional]
  https://www.el-cell.com/what-is-the-self-discharge-rate-of-a-lithium-ion-battery/
- **Dependencies:** chemistry, temperature, state of charge (higher SOC ⇒ faster), age. [secondary specialist]
  https://www.batterydesign.net/battery-cell/self-discharge-of-cells/
- **Temperature rule of thumb:** self-discharge "typically doubles with every 10 °C". [official ref — BU-802b]
- **Reversible vs lost:** most self-discharge is recoverable (charge re-appears on recharging);
  the irreversible part is calendar fade. BU-808 Table 3 (recoverable capacity after 1 year at
  25 °C): **96% at 40% SOC vs 80% at 100% SOC** (≈1.7%/mo effective at full charge). [official ref]
  https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries
- **Known conflict, flagged:** BU-802b *Table 4* ("self-discharge per month of Li-ion") shows up
  to ~20%/mo at 25 °C/100% SOC, which contradicts its own text and BU-808. Treat Table 4 as
  conflating self-discharge with calendar capacity fade; use 1–2%/mo + 3%/mo bias for budgets.
- **Publishing gap:** even flagship cell datasheets omit it — the Panasonic NCR18650B datasheet
  lists no self-discharge parameter. [official datasheet]
- **Derived for 500 mAh:**
  - 1–2%/mo = 5–10 mAh/mo ≈ **7–14 µA** average
  - +3%/mo protection = 15 mAh/mo ≈ **21 µA** average
  - Total ≈ 20–25 mAh/mo ≈ **27–34 µA** ≈ **16–20%** of the 4-month budget (500 mAh / 121.7 d ≈ 171 µA)
  - Shelf-only depletion (charged, device off): **~20 months** at 25 °C; **~10 months** at 35 °C

### 1.2 Alkaline AAA (K860)

- **Rate:** alkaline "2–3% per year (7-10 years shelf life)". [official ref — BU-802b Table 3]
- **Energizer E92:** shelf life **10 years at 21 °C**; internal resistance 150–300 mΩ fresh;
  capacity chart (continuous discharge to 0.8 V at 21 °C) runs **to 1,500 mAh** at the lightest
  currents. [official] https://data.energizer.com/pdfs/e92.pdf
- **Duracell MN2400:** storage 5–30 °C; 156 mΩ @ 1 kHz; no shelf-life figure in the datasheet. [official]
  https://duracell.com/wp-content/uploads/2016/03/MN2400.pdf
- **Duracell CopperTop:** 10-year guarantee in storage. [official site]
  https://duracell.com/products/coppertop-battery
- **Internal resistance** rises as cells deplete (end-of-life voltage sag). [official ref]
  https://batteryuniversity.com/article/bu-802a-how-does-rising-internal-resistance-affect-performance
- **Leakage warning (not drain):** "DON'T – Leave batteries in your device if you suspect it will
  not be used for several months. Many devices don't power off completely when switched off and,
  after time, may cause the batteries inside to leak." [official Duracell]
  https://duracell.com/technology/battery-care-use-and-disposal
- **Derived for a pair (1,000–1,200 mAh usable):** 2–3%/yr ≈ 20–36 mAh/yr ≈ **2.3–4.1 µA** average.

### 1.3 Li-ion vs alkaline at a glance [derived]

- Relative loss per month: Li-Po ≈ 4–5%/mo (incl. protection) vs alkaline ≈ 0.17–0.25%/mo → **~20×**.
- Absolute (these packs): ~27–34 µA vs ~3–4 µA → **~10×**.
- Meaning: shelf self-discharge is a first-class term for the mouse (**16–20%** of each charge);
  for the keyboard it's a rounding error (**<5%**).

---

## 2. Device draw and power management

### 2.1 MX Ergo / MX Ergo S

- Official spec: "Micro-USB rechargeable **Li-Po (500 mAh)** battery; lasts **up to 4 months** a
  full charge", footnote: "Battery life may vary based on user and computing conditions." [official]
  https://www.logitech.com/content/dam/logitech/en/business/pdf/mx-ergo-advanced-wireless-trackball-data-sheet.pdf
- MX Ergo S Quick Start Guide: "A fast rechargeable battery holds power for up to **four months**
  on a full charge. Quick, one-minute charge gives you a full day of usage." [official QSG PDF,
  retrieved during research; product page since retired]
- **Implied average:** 500 mAh / 121.7 d ÷ 24 h = **≈171 µA calendar-average** (24/7 envelope). [derived]
  Logitech does not say whether "4 months" is calendar or active time (see §3), so treat 171 µA
  as the ceiling the firmware+chemistry must average.
- **Sleep mechanism:** sensor runs 1500 fps in use and steps down to **2 fps** in deepest sleep;
  "the depth of sleep is tied to the length of time a mouse is inactive"; auto sleep is a core
  technique, alongside on/off switches. [official Logitech SPM whitepaper]
  https://download01.logitech.com/web/ftp/pub/pdf/bluetooth/smart_power_mgmt_whitepaper.pdf

### 2.2 ERGO K860

- Official FAQ: "**Up to 24 months** using 2x AAA batteries." [official]
  https://www.logitech.com/en-us/shop/p/k860-split-ergonomic
- **Implied average:** 1,000–1,200 mAh / 17,533 h ≈ **57–68 µA** calendar-average; at the E92
  chart-topping 1,500 mAh ≈ 86 µA. [derived]
- **Sleep structure (illustrative, from a Logitech keyboard-power patent):** battery monitor
  wakes every **90 s**; "after two minutes of inactivity, the keyboard **may become completely
  idle**"; voltage→capacity map: 2.8 V ≈ 96%, 2.6 V ≈ 82%, 2.4 V ≈ 25%. [official patent US9184625B1]
  https://patents.google.com/patent/US9184625B1/en

### 2.3 Wake/poll interval and off state

- **No official or measured wake/poll interval exists for either device.** The "HI 1 ms / LO 8 ms"
  figures circulating near unlockable specs belong to the G603 (§4.3). HID++ specs don't publish
  device-side sleep cadence. [not found]
- Both devices have power switches; Logitech's guidance is "Power off your devices when you're
  not using them". [official] https://www.logitech.com/en-us/discover/a/battery-life-and-power
- **Measured off-state current: not found** for either device. Duracell's warning ("many devices
  don't power off completely") implies non-zero, and is a *battery-storage/leakage* note, not a µA figure. [official]
- Practical evidence the switch works: khaytsus — home mouse left always-on "charges every 2
  weeks … could be the device doesn't properly go to sleep"; work mouse switched off = "not very
  often" charges. [community]

### 2.4 Gauge granularity ("full" ≠ 100%)

- Both devices expose a **4-level gauge** via HID++ (MX Ergo: rechargeable flag; K860: not
  rechargeable). Bands collapse to representative values: 0–10%→~5, 11–30%→~20, 31–80%→50,
  81–100%→~90/100. [community/measured — this project's mxbattery]
- Corroboration: Solaar/upower shows the MX Ergo reporting only **90, 50, 20**. [community]
  https://www.reddit.com/r/Trackballs/comments/ehndnm/mx_ergo_what_battery_life_do_you_get/izjcl0g/
- Consequence for the K860: the gauge derives from alkaline voltage, which plateaus — "full"
  can persist for months even as capacity falls. [derived; cf. E92/MN2400 discharge curves (official)]

---

## 3. Usage assumptions and published footnotes

- "Battery life may vary based on user and computing conditions." — the only footnote on the MX
  Ergo claim. [official datasheet]
- **No hours-per-day assumption is published for any Logitech mouse.** [not found]
- "Based on 2 million keystrokes per year in an office environment" appears on Logitech keyboard
  marketing for **other** models (K350/MK850-era reseller copies). It does **not** appear on K860
  product/support pages — do not attribute it to the K860's 24-month figure. [not found on K860; flagged]
- Logitech's own framing (SPM whitepaper, 2005): "everyday use" cordless mouse ⇒ up to 8 months
  on AAs; for power users, "Promising this user six months of alkaline battery life would be
  unrealistic." — i.e. usage profile dominates. [official]
- Logitech discover page: "Bluetooth connections typically consume less battery than 2.4 GHz";
  "Charge batteries between 20% and 80% to preserve long-term battery health". [official]
  https://www.logitech.com/en-us/discover/a/battery-life-and-power

---

## 4. Real-world field data

### 4.1 MX Ergo — owners [community]

Master thread: r/Trackballs "MX Ergo, what battery life do you get?"
https://www.reddit.com/r/Trackballs/comments/ehndnm/mx_ergo_what_battery_life_do_you_get/ ·
also https://www.reddit.com/r/Trackballs/comments/vaceq8/mx_ergo_battery_life/

| Report | Pattern | Per full charge | Calendar-avg [derived] |
|---|---|---|---|
| spicausis, Dec 2022 (izin5um) | daily + weekends, always on, keyboard-heavy, charge when dead | **47, 61, 59, 50, 49 days** | **341–443 µA** |
| drashna (fclebya) | works from home | "about 2 months" | ~342 µA |
| attackofthethumbs (fckp6p6, hvzytet) | office, always on, charge when dead | "every 2ish months"; cell still fine at **3+ years** | ~350 µA |
| jellykick (fckd9v5) | 8 h/day daily, off when away | ~3 months used; "could have gotten about 4 months" | ~170–230 µA (matches official) |
| smilodon142 (fclox3l) | >10 h/day, never off, since release | **~2 weeks** | ~1.5 mA |
| stealthrabbi (vaceq8) | ~2 years, 9 h/weekday, always on | **3 months → 1 month** (degraded) | ~231 → ~694 µA |
| khaytsus (izinh6w) | always on, charges at 50%, logged 28 charges Jan–Nov 2022 | **~10–14 days** | ~870 µA; suspects device "doesn't properly go to sleep" |
| iFixit | guide + genuine replacement cell (533-000121, $19.99) | — | batteries do wear out |

https://www.ifixit.com/Guide/Logitech+MX+Ergo+Battery+Replacement/145871 ·
https://www.ifixit.com/products/logitech-mx-ergo-533-000121-mouse-battery-genuine

Take-aways: official 4 months is achievable (jellykick); typical heavy use = 2–8 weeks; sleep
failure is a recurring failure mode; ~2-year capacity fade cost one owner 2–3× runtime.

### 4.2 ERGO K860 — owners/reviews [community]

| Source | Pattern | Result |
|---|---|---|
| ReviewGeek (Josh Hendrickson; archived 2023-06-10) | **8 h/day × 5 d/wk × 7 months** | original AAAs, software gauge still "full" |
| r/WFH (Sep 2022) | daily programming | "close to a year" |
| r/ErgoMechKeyboards (Apr 2024) | — | "1 year of use on a pair of cheapest JYSK batteries" |
| r/logitech (Nov 2024) | 4+ years ownership | device still in service |

https://web.archive.org/web/20230610073022/https://www.reviewgeek.com/42118/logitech-ergo-k860-review-the-only-keyboard-ill-use/
· https://www.reddit.com/r/WFH/comments/xoqlek/best_keyboard_and_mouse_for_wfh_programing_etc/iq07sw0/
· https://www.reddit.com/r/ErgoMechKeyboards/comments/1c2kfq6/looking_for_a_wireless_ergo_mech_keyboard_that/kzb4vwl/

No credible sub-year report found; the 24-month claim holds for light-moderate office use, and
~1 year is the observed "cheap batteries, heavy use" floor.

### 4.3 Claims checked and corrected

1. **"HI mode 500 h / LO mode 18 months" is the G603 gaming mouse, not the MX Ergo S.**
   Logitech's own page: "in HI mode … up to 500 hours of non-stop gaming. When not gaming,
   simply switch to LO mode … LO mode reports at 8 ms for up to 18 months of use with 2 AA
   batteries." [official copy via Wayback, 2019-04-15]
   https://web.archive.org/web/20190415195108id_/https://www.logitechg.com/en-us/products/gaming-mice/g603-lightspeed-wireless-gaming-mouse.html
   MX Ergo S official figure remains "up to four months".
2. **Reseller listings showing "500 hours" for the MX Ergo S** conflict with every Logitech
   document; pattern matches a 500 *mAh* capacity mis-entry. Treat as erroneous. [community listing, flagged]
3. **"1,590 days" owner report for the MX Ergo: [not found].** No trace in DDG lite, Bing,
   PullPush full-archive search, the owning Reddit threads, or iFixit. The best tracked owner
   logs found total ~266 days (spicausis, 2022) at 47–61 days/charge. The `mxbattery`/README
   basis line citing "owner logs over 1,590 days" is unsupported and should be re-based.
4. **"K860 reports as short as ~6 months": [not found].** Shortest credible data points are
   ~7 months (still "full") and ~1 year.

---

## 5. Synthesis and model

### 5.1 Where the energy goes

**MX Ergo, one charge (500 mAh), official 4-month envelope:**

| Term | Amount | Share |
|---|---|---|
| Self-discharge + protection (20–25 mAh/mo) | 80–100 mAh | 16–20% |
| Device (radio, MCU, sensor — calendar avg) | remainder ≈ 130–140 µA | 80–84% |
| Heavy-use reality | 340 µA–1.5 mA avg → 2–8 weeks/charge | — |

**K860, one set (1,000–1,200 mAh), official 24-month envelope:**

| Term | Amount | Share |
|---|---|---|
| Alkaline self-discharge (2–3%/yr) | 40–70 mAh over 24 mo | 4–6% |
| Device (radio + scan, calendar avg) | ≈ 57–68 µA | 94–96% |

### 5.2 Recommended numbers (per-charge ranges hold; bases need fixing)

- **MX Ergo `61–120 days/charge`: keep**, but replace the basis line "owner logs over 1,590 days"
  with something like: "community charge logs 47–61 d (spicausis, r/Trackballs ehndnm; drashna
  ~2 mo); 3–4 mo at 8 h/day (jellykick); Logitech 'up to 4 months', subject to sleep behavior".
- **K860 `12–24 months/set`: keep**; change "reports as short as ~6 months" → "no credible
  sub-year report found; ~1 year observed floor for heavy use on cheap cells; official 24 months".

### 5.3 Sensitivities worth knowing

- **Temperature:** self-discharge doubles per +10 °C [official ref]. At 30–35 °C the Li-Po
  self-drain alone (8–10%/mo) would consume a "4-month" charge in ~10–12 months of shelf life.
- **Docking at 100%:** Li-ion calendar fade is worst at high SOC + heat (BU-808: 80% remaining
  after 1 yr at 100% SOC vs 96% at 40% SOC; Logitech advises 20–80% charging). A mouse kept
  topped up on its base ages faster than one cycled.
- **Sleep bugs:** one owner's ~870 µA draw ("could be the device doesn't properly go to sleep")
  is ~5× official; the power switch is the only reliable mitigation ("work mouse I turn off …
  pretty rare" charging).
- **Alkaline leakage:** for K860s stored unused for months, the risk is leakage from residual
  switch-off drain, not self-discharge — pull the cells (Duracell warning).

---

## 6. Explicit "not found" list

1. MX Ergo "1,590 days" owner report — no trace in any searched source.
2. Measured sleep/idle microamp draw for MX Ergo, K860, or the Unifying receiver — no FCC
   exhibits, teardowns, or vendor documents located.
3. Official or measured wake/poll interval for either device (HI/LO 1ms/8ms belongs to G603).
4. Measured off-state current for either device.
5. K860-specific "2 million keystrokes/year" footnote — exists for other Logitech keyboards only.
6. Any credible K860 battery report shorter than ~7 months.
7. A published hours-per-day usage assumption for any Logitech mouse battery claim.
