from ape import accounts, project


def main():
    acct = accounts.load("deployer_account")
    uniswap_v2_factory_address = "0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F"
    weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    grain = ""
    UniswapV2Factory = project.uniswap_v2_factory.at(uniswap_v2_factory_address)
    UniswapV2Factory.createPair(weth, grain, sender=acct)
