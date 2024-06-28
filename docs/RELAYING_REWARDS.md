# Relaying rewards

Paloma incentivices transaction relaying by enabling relayers to charge a 
relaying fee, defined as a multiple of the total transaction cost. With a
setting of 105%, a relayer will be eligible to claim rewards totalling to the
cost of the transaction plus an additional 5% service fee.

Rewards are saved up and paid out in GRAIN tokens upon claim request.

## Reimbursements

### For uploading a new version of compass

Reimbursements will continue to stay manual for now. 
In the future, we can potentially route this the same way as regular user contract uploads,
and therefore reimburse directly.

### For relaying user content

Relaying user content is the primary driver of the Paloma network and the main incentive
for relayers to offer their services. These include arbitrary code execution, as well
as deploying smart contracts. Both are routed via the same function, `submit_logic_call`,
and require the author of the call to have made a deposit on compass beforehand.

From this deposit, precalculated cuts are being taken and transferred to the _security_ and
_community funds_, as well as the _claimable rewards_ for the relayer of the message, who
may later request a withdrawal.


### For relaying infrastructure messages

To support the ongoing operation of the Paloma network, relaying infrastructure related
content forms the backbone of our operations. These messages include:

- `update_valset`
- `submit_batch`
- `bridge_community_tax_to_paloma`

Senders relaying these messages will be reimbursed for the spent gas from the _security wallet_. 
In case the security wallet balance reaches `0`, relayed messages are no longer covered
for reimbursement. The security wallet can be topped up in regular intervals to ensure
uninterrupted coverage.

### Topping up security funds

A manual call to `security_fee_topup()` can be made in case the `rewards_security_wallet`
balance is getting low in order to ensure uninterrupted coverage of infrastructure
reimbursements.

### Bridging the community tax back to Paloma

A fraction of the fees generated during user content relays is being stored in a
_community wallet_, which will be bridged back to Paloma in regular intervals.
Relaying a triggering call will be covered for reimbursement by the _security wallet_.

### Withdrawing rewards

Relayers who have amassed a claimable reward balance may submit a direct call
to `withdraw(amount:uint256, exchange:address)`, with the amount they wish to
withdraw, as well as the exchange to be used for the transfer of COIN to GRAINS.
The call needs to be made from the same address registered with Paloma for each
given chain.


## Upgrading Compass

Compass now takes a new constructor input parameter, which is the address
of the old version of compass on the same chain. After successful deployment, but
BEFORE Paloma switches versions, a call will be issued to the old compass to 
`send_books()`, which will then relay the state of the internal book keeping
along with any left funds to `receive_books()` on the new compass version.

After that, Paloma will switch to the new version of compass. To ensure 
no state desync during the time of this intermediate upgrade step, Paloma
will not be relaying any other types of messages until the upgrade is complete.

# Architectural decisions

### Ensuring balance consistency

Internal balances are represented as hash maps, which do not have a concept of length
and cannot be iterated over to verify balance integrity.
Therefore, we maintain additional counter variables `total_funds` and `total_claims`, 
so that we can always assert that 
`self.balance = total_funds + total_claims + rewards_community_wallet` + `rewards_security_wallet`


### Security and Community fees

The original architectural design was aimed at keeping gas cost as low as
possible, and we continue to make this a priority with our contracts.
However, with the necessary addition of on-contract accounting, this 
constraint has been slightly loosened.

In order to stay ahead of market developments and protect the community from
the risks of price fluctuation, we have decided to transfer funds to community
and security fee wallets with every executed relay (as opposed to after
deposit only). This slightly increases gas, but makes sure the Paloma
relayer network can still be fully reimbursed for valset updates even during
times of high slippage.

### No book keeping on Paloma

The original intent was to keep a shadow copy of the books on Compass on 
Paloma. With the development of gas price prediction of Paloma, this gives
little to no advantage at the moment.
