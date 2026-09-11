# MT5 Auto-Entry Setup

Three pieces work together:

1. **index.html** — your existing app. Analyzes a chart screenshot with Gemini,
   then (if auto-send is on) POSTs the BUY/SELL signal to the bridge server.
2. **bridge_server.py** — a tiny local relay. Holds the latest signal in memory.
3. **LiquiditySignalEA.mq5** — an MT5 Expert Advisor that polls the bridge
   every few seconds and places the trade with SL/TP attached.

## 1. Run the bridge server

On the PC that runs your MT5 terminal:

```
pip install flask
python bridge_server.py
```

Open `bridge_server.py` and change `SHARED_SECRET` to your own password —
use the same value everywhere in step 3 and 4.

Find that PC's LAN IP (Windows: `ipconfig`, look for IPv4 Address, e.g.
`192.168.1.50`). If your phone/browser and MT5 are on the same PC, you can
just use `127.0.0.1` instead.

## 2. Install the EA in MT5

- In MT5: File > Open Data Folder > MQL5 > Experts. Copy
  `LiquiditySignalEA.mq5` there.
- Open MetaEditor (F4 in MT5), open the file, compile it (F7).
- Tools > Options > Expert Advisors tab > check "Allow WebRequest for
  listed URL" > add your bridge address, e.g. `http://127.0.0.1:5000`
  (must match exactly, including port).
- Drag the EA onto any chart. It trades whatever symbol each signal
  specifies — not just the chart it's attached to.
- In the EA's input dialog, set `SharedSecret` to match `bridge_server.py`.
- Make sure the AutoTrading button (top toolbar) is enabled/green.

**Important input: `AllowLiveTrading` defaults to `false`.** On a real-money
account, the EA will log signals but refuse to place trades until you
deliberately flip this to `true`. Prove the whole pipeline out on a demo
account first — for real, for at least a few weeks.

## 3. Configure the app

In the browser app, tap the gear icon and fill in the "MT5 Auto-Entry
Bridge" section:

- **Bridge URL** — e.g. `http://192.168.1.50:5000`
- **Shared secret** — same string as `bridge_server.py` and the EA
- **Default symbol** — used if Gemini can't read the pair off the chart
  image (e.g. `EURUSD`). Must exactly match the symbol name in your MT5
  Market Watch (brokers sometimes add suffixes like `EURUSD.a`).
- Check **"Auto-send every BUY/SELL signal to MT5"**

From then on, every time you analyze a chart and get a BUY or SELL, it's
sent to the bridge automatically — no extra tap. The result screen shows
an "MT5 Auto-Entry" status line confirming it was sent (or explaining why
it wasn't, e.g. missing symbol or SL/TP).

## Built-in safety checks (already in the code)

- **Real-account block** — trading is refused on a live account unless
  `AllowLiveTrading=true` is set deliberately in the EA.
- **Stale/mismatched price rejection** — before placing a BUY, the EA
  checks the stop loss is below and take profit is above the *current
  live* ask price (and the mirror for SELL). If the screenshot's levels
  don't make sense against live price anymore — because time passed
  between screenshotting and executing — the trade is rejected and logged
  instead of firing blind.
- **Risk-based position sizing** — lot size is computed from
  `RiskPercent` (default 1%) of account balance and the actual stop
  distance, not a fixed lot size.
- **One-trade-at-a-time** — by default, the EA won't open a new position
  while one of its own positions is still open (toggle via
  `OneOpenTradeAtATime`).
- **Signal deduplication** — each signal has an increasing ID; the EA
  only acts on IDs newer than the last one it processed.
- **Stale signal expiry** — the bridge refuses to hand a signal to the EA
  if it's more than 2 minutes old (`MAX_SIGNAL_AGE_SECONDS`), in case the
  EA was offline when it was sent.

## Real limitations to know about

- **The AI reads price levels off a static screenshot, not a live feed.**
  The longer the gap between taking the screenshot and the EA executing,
  the more likely price has moved and the trade gets rejected by the
  sanity check above (which is the safe outcome) — or, worse, still
  passes the sanity check but on a level that's no longer as good as it
  looked. Act on signals quickly.
- **Symbol name matching is exact-string.** If Gemini reads "EURUSD" off
  the chart but your broker lists it as "EURUSD.a" or "EURUSD_i", the EA
  will fail to find the symbol. Setting a correct "Default symbol" per
  instrument you screenshot is the reliable path.
- **This is not financial advice**, and none of these safety checks make
  the underlying strategy profitable — they only stop obviously broken
  trades (stale prices, oversized risk, duplicate entries) from firing.
  Run it on a demo account for a meaningful stretch before ever
  considering real money, and never risk more than you can afford to
  lose.
