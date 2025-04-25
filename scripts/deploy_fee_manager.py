from ape import accounts, networks, project


def main():
    acct = accounts.load("deployer_account")
    priority_fee = networks.active_provider.priority_fee
    max_base_fee = int(networks.active_provider.base_fee * 1.2) + priority_fee
    project.FeeManager.deploy(max_fee=max_base_fee, max_priority_fee=priority_fee, sender=acct)

