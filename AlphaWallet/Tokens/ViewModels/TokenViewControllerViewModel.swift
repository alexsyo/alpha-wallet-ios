// Copyright © 2018 Stormbird PTE. LTD.

import Foundation
import UIKit
import BigInt
import PromiseKit

struct TokenViewControllerViewModel {
    private let transactionType: TransactionType
    private let session: WalletSession
    private let tokensStore: TokensDataStore
    private let transactionsStore: TransactionsStorage
    private let assetDefinitionStore: AssetDefinitionStore
    private let swapTokenActionsService: SwapTokenActionsService

    var token: TokenObject? {
        switch transactionType {
        case .nativeCryptocurrency:
            //TODO might as well just make .nativeCryptocurrency hold the TokenObject instance too
            return TokensDataStore.etherToken(forServer: session.server)
        case .ERC20Token(let token, _, _):
            return token
        case .ERC875Token, .ERC875TokenOrder, .ERC721Token, .ERC721ForTicketToken, .dapp, .tokenScript, .claimPaidErc875MagicLink:
            return nil
        }
    }

    let recentTransactions: [Transaction]

    var actions: [TokenInstanceAction] {
        guard let token = token else { return [] }
        let xmlHandler = XMLHandler(token: token, assetDefinitionStore: assetDefinitionStore)
        var actionsFromTokenScript = xmlHandler.actions

        if actionsFromTokenScript.isEmpty {
            switch token.type {
            case .erc875:
                return []
            case .erc721:
                return []
            case .erc721ForTickets:
                return []
            case .erc20:
                let actions: [TokenInstanceAction] = [
                    .init(type: .erc20Send),
                    .init(type: .erc20Receive)
                ]

                return actions + swapTokenActionsService.actions(token: token)
            case .nativeCryptocurrency:
                let actions: [TokenInstanceAction] = [
                    .init(type: .erc20Send),
                    .init(type: .erc20Receive)
                ]
                switch token.server {
                case .xDai:
                    return [.init(type: .xDaiBridge)] + actions + swapTokenActionsService.actions(token: token)
                case .main, .kovan, .ropsten, .rinkeby, .poa, .sokol, .classic, .callisto, .goerli, .artis_sigma1, .artis_tau1, .binance_smart_chain, .binance_smart_chain_testnet, .heco, .heco_testnet, .custom:
                    return actions + swapTokenActionsService.actions(token: token)
                }
            }
        } else {
            switch token.type {
            case .erc875, .erc721, .erc721ForTickets:
                return actionsFromTokenScript
            case .erc20:
                return actionsFromTokenScript + swapTokenActionsService.actions(token: token)
            case .nativeCryptocurrency:
                let xDaiBridgeActions: [TokenInstanceAction]
                switch token.server {
                case .xDai:
                    xDaiBridgeActions = [.init(type: .xDaiBridge)]
                case .main, .kovan, .ropsten, .rinkeby, .poa, .sokol, .classic, .callisto, .goerli, .artis_sigma1, .artis_tau1, .binance_smart_chain, .binance_smart_chain_testnet, .heco, .heco_testnet, .custom:
                    xDaiBridgeActions = []
                }

                //TODO we should support retrieval of XML (and XMLHandler) based on address + server. For now, this is only important for native cryptocurrency. So might be ok to check like this for now
                if let server = xmlHandler.server, server.matches(server: token.server) {
                    actionsFromTokenScript += swapTokenActionsService.actions(token: token)
                    return xDaiBridgeActions + actionsFromTokenScript
                } else {
                    //TODO .erc20Send and .erc20Receive names aren't appropriate
                    let actions: [TokenInstanceAction] = [
                        .init(type: .erc20Send),
                        .init(type: .erc20Receive)
                    ]

                    return xDaiBridgeActions + actions + swapTokenActionsService.actions(token: token)
                }
            }
        }
    }

    var tokenScriptStatus: Promise<TokenLevelTokenScriptDisplayStatus> {
        if let token = token {
            let xmlHandler = XMLHandler(token: token, assetDefinitionStore: assetDefinitionStore)
            return xmlHandler.tokenScriptStatus
        } else {
            assertImpossibleCodePath()
            return .value(.type2BadTokenScript(isDebugMode: false, message: "Unknown", reason: nil))
        }
    }

    var fungibleBalance: BigInt? {
        switch transactionType {
        case .nativeCryptocurrency:
            let string: String? = session.balanceViewModel.value?.amountShort
            return string.flatMap { EtherNumberFormatter.full.number(from: $0, decimals: session.server.decimals) }
        case .ERC20Token(let tokenObject, _, _):
            return tokenObject.valueBigInt
        case .ERC875Token, .ERC875TokenOrder, .ERC721Token, .ERC721ForTicketToken, .dapp, .tokenScript, .claimPaidErc875MagicLink:
            return nil
        }
    }

    init(transactionType: TransactionType, session: WalletSession, tokensStore: TokensDataStore, transactionsStore: TransactionsStorage, assetDefinitionStore: AssetDefinitionStore, swapTokenActionsService: SwapTokenActionsService) {
        self.transactionType = transactionType
        self.session = session
        self.tokensStore = tokensStore
        self.transactionsStore = transactionsStore
        self.assetDefinitionStore = assetDefinitionStore
        self.swapTokenActionsService = swapTokenActionsService

        switch transactionType {
        case .nativeCryptocurrency:
            self.recentTransactions = Array(transactionsStore.objects.lazy
                    .filter({ $0.state == .completed || $0.state == .pending })
                    .filter({ $0.operation == nil })
                    .filter({ $0.value != "" && $0.value != "0" })
                    .prefix(3))
        case .ERC20Token(let token, _, _):
            self.recentTransactions = Array(transactionsStore.objects.lazy
                    .filter({ $0.state == .completed || $0.state == .pending })
                    .filter({
                        if let operation = $0.operation {
                            return operation.operationType == .erc20TokenTransfer
                        } else {
                            return false
                        }})
                    .filter({ $0.operation?.contract.flatMap { token.contractAddress.sameContract(as: $0) } ?? false })
                    .prefix(3))
        case .ERC875Token, .ERC875TokenOrder, .ERC721Token, .ERC721ForTicketToken, .dapp, .tokenScript, .claimPaidErc875MagicLink:
            self.recentTransactions = []
        }
    }

    var destinationAddress: AlphaWallet.Address {
        return transactionType.contract
    }

    var backgroundColor: UIColor {
        return Colors.appBackground
    }

    var showAlternativeAmount: Bool {
        guard let currentTokenInfo = tokensStore.tickers?[destinationAddress], currentTokenInfo.price_usd > 0 else {
            return false
        }
        return true
    }

    var sendButtonTitle: String {
        return R.string.localizable.send()
    }

    var receiveButtonTitle: String {
        return R.string.localizable.receive()
    }
}
