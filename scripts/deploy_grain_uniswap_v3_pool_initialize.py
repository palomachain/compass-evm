from ape import accounts, project
import math


def main():
    acct = accounts.load("deployer_account")
    pool = ""
    grain_amount = 1000
    ETH_amount = 1
    sqrtPriceX96 = int(math.sqrt(grain_amount / ETH_amount) * 2 ** 96)  # WETH address < grain address
    sqrtPriceX96 = int(math.sqrt(ETH_amount / grain_amount) * 2 ** 96)  # grain address < WETH address
    UniswapV3Pool = project.uniswap_v3_pool.at(pool)

    UniswapV3Pool.initialize(sqrtPriceX96, sender=acct)
