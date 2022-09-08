# Compass-EVM

This smart contract is to make possible to run any other smart contract with arbitrary transaction data.

This is written in Vyper.

Usage example:

- You send 25 DAI to the Compass-EVM contract, specifying which address on the Paloma chain should recieve the synthetic DAI.
- Validators on the Paloma blockchain see that this has happened and mint 25 synthetic DAI for the address you specified on the Paloma chain.
- You send the 25 synthetic DAI to Jim on the Paloma chain.
- Jim sends the synthetic DAI to Turnstone module on the Paloma blockchain, specifying which Ethereum address should receive it.
- The Paloma validators burn the synthetic DAI on the Paloma blockchain and unlock 25 DAI for Jim on Ethereum

## Security model

The Compass-EVM contract is basically a validator-set multisig with a few tweaks. Even though it is designed to be used with a consensus process on Paloma, the Compass-EVM contract itself encodes nothing about this consensus process. There are three main operations- update_valset, submit_logic_call.
- update_valset updates the signers on the multisig, and their relative powers. This mirrors the validator set on the Paloma blockchain, so that all the Paloma validators are signers, in proportion to their staking power on the Paloma chain. An update_valset transaction must be signed by 2/3's of the current valset to be accepted.
- submit_logic_call is used to submit a arbitrary transactions to another smart contract. The logic call must be signed by 2/3's of the current valset.

### update_valset

A valset consists of a list of validator's Ethereum addresses, their voting power, and an id for the entire valset. update_valset takes a new valset, the current valset, and the signatures of the current valset over the new valset.

Then, it checks the supplied current valset against the saved checkpoint. This requires some explanation. Because valsets contain over 100 validators, storing these all on the Ethereum blockchain each time would be quite expensive. Because of this, we only store a hash of the current valset, then let the caller supply the actual addresses, powers, and valset_id. We call this hash the checkpoint. This is done with the function make_checkpoint.

Once we are sure that the valset supplied by the caller is the correct one, we check that the new valset id is higher than current valset id. This ensures that old valsets cannot be submitted because their id is too low. Note: the only thing we check from the new valset is the id. The rest of the new valset is passed in the arguments to this method, but it is only used recreate the checkpoint of the new valset. If we didn't check the id, it would be possible to pass in the checkpoint directly.

Now, we make a checkpoint from the submitted new valset, using make_checkpoint again. In addition to be used as a checkpoint later on, we first use it as a digest to check the current valset's signature over the new valset. We use check_validator_signatures to do this.

check_validator_signatures takes a valset, an array of signatures, a hash, and a power threshold. It checks that the powers of all the validators that have signed the hash add up to the threshold. This is how we know that the new valset has been approved by at least 2/3s of the current valset. We iterate over the current valset and the array of signatures, which should be the same length. For each validator, we first check if the signature is all zeros. This signifies that it was not possible to obtain the signature of a given validator. If this is the case, we just skip to the next validator in the list. Since we only need 2/3s of the signatures, it is not required that every validator sign every time, and skipping them stops any validator from being able to stop working.

If we have a signature for a validator, we verify it, throwing an error if there is something wrong. We also increment a cumulative_power counter with the validator's power. Once this is over the threshold, we break out of the loop, and the signatures have been verified! If the loop ends without the threshold being met, we throw an error. Because of the way we break out of the loop once the threshold has been met, if the valset is sorted by descending power, we can usually skip evaluating the majority of signatures. To take advantage of this gas savings, it is important that valsets be produced by the validators in descending order of power.

At this point, all of the checks are complete, and it's time to update the valset! This is a bit anticlimactic, since all we do is save the new checkpoint over the old one. An event is also emitted.

### submit_logic_call

This is how the Compass-EVM run the arbitrary transaction to the other smart contract.

We start with some of the same checks that are done in update_valset- checking the supplied current valset against the checkpoint.

We also check if the message_id is used. This stores an id for each ERC20 handled by Compass-EVM. The purpose of this id is to ensure that old logic call cannot be submitted again. It is also used on the Paloma chain to clean up old batches that were never submitted and whose id is now too low to ever submit.

We check the current validator's signatures over the hash of the logic call, using the same method used above to check their signatures over a new valset.

Now we are ready. We run the arbitrary transaction to the logic contract.

The payload data should be less than 1024 bytes.

## Events

We emit 2 different events, each of which has a distinct purpose. One contains a field called message_id, which is used by the Paloma chain to ensure that the events are not out of order. This should updated each time one of the events is emitted.
The other one emits valset_id and checkpoint when valset_id is updated.

### LogicCallEvent

This contains information about a logic_call transaction that has been successfully processed. It contains the message_id and the logic_contract address, and payload data. The Paloma chain can identify the transaction from this information.

### ValsetUpdated

This is emitted whenever the valset is updated. It does not contain the _eventNonce, since it is never brought into the Paloma state. It is used by relayers when they call submit_logic_call or update_valset, so that they can include the correct validator signatures with the transaction.
