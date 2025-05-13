## Hawk High

[//]: # "contest-details-open"

### About

Welcome to **Hawk High**, enroll, avoid bad reviews, and graduate!!!

You have been contracted to review the upgradeable contracts for the Hawk High School which will be launched very soon.

These contracts utilize the UUPSUpgradeable library from OpenZeppelin.

At the end of the school session (4 weeks), the system is upgraded to a new one.

### Actors

- `Principal`: In charge of hiring/firing teachers, starting the school session, and upgrading the system at the end of the school session. Will receive 5% of all school fees paid as his wages. can also expel students who break rules.
- `Teachers`: In charge of giving reviews to students at the end of each week. Will share in 35% of all school fees paid as their wages.
- `Student`: Will pay a school fee when enrolling in Hawk High School. Will get a review each week. If they fail to meet the cutoff score at the end of a school session, they will be not graduated to the next level when the `Principal` upgrades the system.

### Invariants

- A school session lasts 4 weeks
- For the sake of this project, assume USDC has 18 decimals
- Wages are to be paid only when the `graduateAndUpgrade()` function is called by the `principal`
- Payment structure is as follows:
  - `principal` gets 5% of `bursary`
  - `teachers` share of 35% of bursary
  - remaining 60% should reflect in the bursary after upgrade
- Students can only be reviewed once per week
- Students must have gotten all reviews before system upgrade. System upgrade should not occur if any student has not gotten 4 reviews (one for each week)
- Any student who doesn't meet the `cutOffScore` should not be upgraded
- System upgrade cannot take place unless school's `sessionEnd` has reached

### Resources

Check out [this](https://updraft.cyfrin.io/courses/advanced-foundry/upgradeable-smart-contracts/introduction-to-upgradeable-smart-contracts) to learn more about Upgradeable Contracts

[//]: # "contest-details-close"
[//]: # "scope-open"

### Scope

```
├── src
│   ├── LevelOne.sol
│   └── LevelTwo.sol
```

### Compatibilities

- Chain: EVM Compatible
- Token: USDC

[//]: # "scope-close"
[//]: # "getting-started-open"

### Setup

```bash
    git clone https://github.com/CodeHawks-Contests/2025-05-hawk-high.git
```

```bash
    make setup
```

```bash
    forge build
```

### Tests

```bash
    forge test
```

[//]: # "getting-started-close"
[//]: # "known-issues-open"

None reported! 😉

[//]: # "known-issues-close"
