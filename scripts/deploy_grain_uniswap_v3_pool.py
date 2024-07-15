from ape import accounts, project


def main():
    acct = accounts.load("deployer_account")
    uniswap_v3_factory_address = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
    weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    grain = ""
    fee = 3000
    UniswapV3Factory = project.uniswap_v3_factory.at(uniswap_v3_factory_address)
    UniswapV3Factory.createPool(weth, grain, fee, sender=acct)
