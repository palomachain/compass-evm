from ape import accounts, project


def main():
    acct = accounts.load("deployer_account")
    curve_twocrypto_factory_address = "0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F"
    weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    grain = ""
    name = "WETH/Grain"
    symbol = "WETHGRAIN"
    coins = [weth, grain]
    implementation_id = 0
    A = 400000
    gamma = 145000000000000
    mid_fee = 26000000
    out_fee = 45000000
    fee_gamma = 230000000000000
    allowed_extra_profit = 2000000000000
    adjustment_step = 146000000000000
    ma_exp_time = 866
    initial_price = 4359000000000
    CurveTwocryptoFactory = project.curve_twocrypto_factory.at(curve_twocrypto_factory_address)
    CurveTwocryptoFactory.deploy_pool(
        name, symbol, coins, implementation_id, A, gamma, mid_fee, out_fee, fee_gamma, allowed_extra_profit,
        adjustment_step, ma_exp_time, initial_price, sender=acct)
