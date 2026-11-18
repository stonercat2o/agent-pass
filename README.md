# Agent Pass

**A daily free claim for Binance Agent ID holders, on BNB Chain.**

Every day (UTC), any wallet holding a Binance Agent ID can claim one
soulbound badge from the Agent Pass contract — free, with no payment and no
token approvals. Claiming on consecutive days builds a public streak. The
badge is a non-transferable ERC-721 whose artwork and metadata name the day
it was earned, served as a fully self-contained data URI (no external
hosting anywhere in the product).

- Contract: [`contracts/AgentPass.sol`](contracts/AgentPass.sol)
- Web page: [`web/index.html`](web/index.html) (single file, standard
  injected-wallet connect — no QR-code or pairing-code login)
- Agent ID registry (SPACE ID, BNB Chain mainnet):
  `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`

## Agent ID usage description (for the hackathon submission form)

> Agent Pass is a daily free claim built entirely around Binance Agent ID.
> The product's core mechanic — one claim per person per day — is only
> possible because of what Agent ID is: a non-transferable, one-per-person
> on-chain identity. On every claim, the contract checks the caller's
> balance in the official SPACE ID Agent ID registry
> (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F); no Agent ID, no claim.
>
> Agent ID provides three things the product is built on:
>
> 1. **Access control / eligibility.** Holding an Agent ID is the only
>    credential. There is no sign-up, allowlist, account or API key — the
>    identity check happens on-chain, in the same transaction as the claim.
> 2. **Sybil resistance.** Because an Agent ID is limited to one per person
>    and cannot be transferred or sold, "one claim per address per day" is
>    in practice "one claim per person per day", without captchas, deposits
>    or social tasks.
> 3. **Persistent identity for streaks.** Badges and streaks accrue to a
>    lasting agent identity rather than a throwaway wallet, which makes the
>    daily streak meaningful and publicly readable by any other dApp
>    (`streakOf`, `claimsOf`, `uniqueClaimers`, `totalClaims` are all
>    public views).
>
> Claiming is deliberately frictionless and safe: it is free (the claimer
> only pays their own network gas), it requests no token approvals, the
> contract never holds user funds, and badges are soulbound so the system
> cannot be farmed for resale.

## How it works

1. The user opens the web page and connects the wallet that holds their
   Agent ID (standard `window.ethereum` connect).
2. The page reads the contract: does this wallet hold an Agent ID? Is
   today's claim still available? What is the user's streak, and the global
   counters (unique claimers, total claims)?
3. The user clicks **Claim**. `claim()` verifies the Agent ID against the
   registry, enforces one claim per address per UTC day, updates the
   streak (consecutive days extend it; a missed day restarts it at 1), and
   mints the day's soulbound badge.

## Safety properties

- **No payments, ever.** `claim()` is non-payable; attaching value reverts.
  The contract has no `receive`/`fallback`, no withdrawal function and no
  fee mechanism — it can never hold user funds.
- **No approvals.** The contract never asks for ERC-20/ERC-721 approvals.
  Badge approvals and transfers revert by design (soulbound).
- **Minimal owner powers.** The owner (deployer) can only `pause()` /
  `unpause()` claims. There is no owner minting, no upgrade path, no
  parameter that can be changed after deployment (the registry address is
  `immutable`).
- **No promised returns.** Badges carry no monetary value and the page says
  so. There is no trading functionality.
- **Open and verifiable.** One small, commented Solidity file, MIT
  licensed, compiled with solc 0.8.26 (optimizer 200 runs, EVM target
  Shanghai).

## Build & test

Requirements: Node.js 18+ (developed on Node 24). No global tooling —
solc, ethers and Ganache are npm dev dependencies.

```bash
npm install        # once
npm run compile    # solc -> build/*.json (abi + bytecode)
npm test           # compile + full unit-test suite on an in-process EVM
npm run deploy:local   # deployment gas measurement on a fresh local chain
```

The test suite deploys a mock Agent ID registry (the real registry is
mainnet-only) and covers: non-holders cannot claim; a holder's first claim
mints badge #1 with a `Claimed` event; a second claim the same day reverts;
claiming works again after the UTC day rolls over (EVM time travel);
streak growth and streak reset after a skipped day; global and per-user
counters and the unique-claimer list; badges reject transfers and
approvals; pause blocks claims and unpause restores them; `claim()` is
non-payable and the contract balance stays zero; `tokenURI` decodes to
JSON whose SVG names the mint day.

**Latest local results: 12 tests, 12 passed.**

## Measured gas (local, solc 0.8.26, optimizer 200 runs)

| Operation | gasUsed | @ 1 gwei | @ 3 gwei |
| --- | --- | --- | --- |
| Deploy `AgentPass` | 1,484,205 | 0.001484 BNB | 0.004453 BNB |
| One `claim()` (first claim) | 238,524 | 0.000239 BNB | 0.000716 BNB |

Deployment was measured with the constructor wired to the real mainnet
registry address, exactly as a mainnet deployment would be.

## Deployment status / notes

- **Mainnet (chain 56): not deployed.** Deployment is a separate, later
  step that requires explicit approval; the deploying account only needs
  ~0.005 BNB to cover deployment at up to ~3 gwei.
- **Testnet (chain 97): blocked at funding.** A testnet-only burner key
  was generated at `.deployer-testnet.key` (mode 600, gitignored, never
  committed) with address `0x84405DD80AA1990e3D138378A22e48a73627fD62`.
  The official BNB Chain testnet faucet is a login-gated web flow (no
  unauthenticated API), so the burner could not be funded autonomously.
  Send it a little tBNB and `scripts/deploy-local.js` can be adapted to
  deploy to chain 97 in minutes.
- After any real deployment, update `CONFIG` at the top of
  `web/index.html` (`chainId`, `contractAddress`, `explorer`).

## Contract interface (views the page uses)

| Function | Meaning |
| --- | --- |
| `hasAgentId(address)` | Wallet currently holds an Agent ID |
| `canClaimToday(address)` | Wallet could claim right now |
| `streakOf(address)` | Current consecutive-day streak |
| `claimsOf(address)` | Lifetime claims by this wallet |
| `balanceOf(address)` | Badges held (ERC-721) |
| `totalClaims()` | All claims, all time |
| `uniqueClaimers()` | Distinct wallets that ever claimed |
| `claimerAt(uint256)` | Unique claimer by index |
| `currentDay()` / `dayOf(tokenId)` | Current UTC day index / a badge's day |
| `agentIdRegistry()` | The registry the contract gates on |
| `claim()` | Claim today's badge (emits `Claimed`) |

## License

MIT
