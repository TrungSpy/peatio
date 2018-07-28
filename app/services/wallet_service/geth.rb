# encoding: UTF-8
# frozen_string_literal: true

module WalletService
  class Geth < Base

    DEFAULT_ETH_FEE = { gas_limit: 30_000, gas_price: 10_000_000_000 }.freeze
    DEFAULT_ERC20_FEE_VALUE =  { gas_limit: 100_000, gas_price: 10_000_000_000 }.freeze

    def create_address(options = {})
      client.create_address!(options)
    end

    def collect_deposit!(deposit, options={})
      destination_address = destination_wallet(deposit).address
      if deposit.currency.code.eth?
        collect_eth_deposit!(deposit, destination_address, options)
      else
        collect_erc20_deposit!(deposit, destination_address, options)
      end
    end

    private

    def collect_eth_deposit!(deposit, destination_address, options={})
      # Default values for Ethereum tx fees.
      options = DEFAULT_ETH_FEE.merge options

      # We can't collect all funds we need to subtract gas fees.
      amount = deposit.amount_to_base_unit! - options[:gas_limit] * options[:gas_price]
      pa = deposit.account.payment_address
      client.create_eth_withdrawal!(
        { address: pa.address, secret: pa.secret },
        { address: destination_address},
        amount,
        options
      )
    end

    def collect_erc20_deposit!(deposit, destination_address, options={})
      pa = deposit.account.payment_address


      client.create_erc20_withdrawal!(
          { address: pa.address, secret: pa.secret },
          { address: destination_address },
          deposit.amount_to_base_unit!,
          options.merge(contract_address: deposit.currency.erc20_contract_address )
      )
    rescue WalletClient::Error => e
      # In case of deposit collection failure we need to deposit more fees.
      # TODO: check if balance less than MAX_ERC20_FEES_VALUE and no pending transactions for this payment address
      deposit_eth_for_fees(pa.address) # if client.load_eth_balance < MAX_ERC20_FEES_VALUE && no pending transactions for this payment address
      raise e
    end

    def destination_wallet(deposit)
      # TODO: Dynamicly check wallet balance and select where to send funds.
      # For keeping it simple we will collect all funds to hot wallet.
      Wallet
        .active
        .withdraw
        .find_by(blockchain_key: deposit.currency.blockchain_key, kind: :hot)
    end

    def eth_fees_wallet
      Wallet
        .active
        .withdraw
        .find_by(currency_id: :eth, kind: :hot)
    end

    def deposit_eth_for_fees(destination_address, options={})
      fees_wallet = eth_fees_wallet
      options = DEFAULT_ERC20_FEE_VALUE.merge options
      amount = options[:gas_limit] * options[:gas_price]

      client.create_eth_withdrawal!(
          { address: fees_wallet.address, secret: fees_wallet.secret },
          { address: destination_address},
          amount
      )
    end
  end
end
