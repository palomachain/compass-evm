from ape import accounts, project


def main():
    acct = accounts.load("deployer_account")
    pool = ""
    curve_twocrypto_factory_address = "0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F"
    CurveTwocryptoFactory = project.curve_twocrypto_factory.at(curve_twocrypto_factory_address)
    CurveTwocryptoFactory.deploy_gauge(pool, sender=acct)
