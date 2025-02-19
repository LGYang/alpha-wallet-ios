// Copyright © 2020 Stormbird PTE. LTD.

import Foundation
import BigInt
import PromiseKit
import web3swift
import Combine

protocol EventSourceCoordinatorForActivitiesType: AnyObject {
    func start()
}

class EventSourceCoordinatorForActivities: EventSourceCoordinatorForActivitiesType {
    private var wallet: Wallet
    private let config: Config
    private let tokensDataStore: TokensDataStore
    private let assetDefinitionStore: AssetDefinitionStore
    private let eventsDataStore: EventsActivityDataStoreProtocol
    private var isFetching = false
    private var rateLimitedUpdater: RateLimiter?
    private let queue = DispatchQueue(label: "com.EventSourceCoordinatorForActivities.updateQueue")
    private let enabledServers: [RPCServer]
    private var cancellable = Set<AnyCancellable>()

    init(wallet: Wallet, config: Config, tokensDataStore: TokensDataStore, assetDefinitionStore: AssetDefinitionStore, eventsDataStore: EventsActivityDataStoreProtocol) {
        self.wallet = wallet
        self.config = config
        self.tokensDataStore = tokensDataStore
        self.assetDefinitionStore = assetDefinitionStore
        self.eventsDataStore = eventsDataStore
        self.enabledServers = config.enabledServers
    }

    func start() {
        setupWatchingTokenChangesToFetchEvents()
        setupWatchingTokenScriptFileChangesToFetchEvents()
    }

    private func setupWatchingTokenChangesToFetchEvents() {
        tokensDataStore
            .enabledTokenObjectsChangesetPublisher(forServers: config.enabledServers)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.fetchEthereumEvents()
            }.store(in: &cancellable)
    }

    private func setupWatchingTokenScriptFileChangesToFetchEvents() {
        assetDefinitionStore.bodyChange
            .receive(on: RunLoop.main)
            .compactMap { self.tokensDataStore.tokenObject(forContract: $0) }
            .sink { [weak self] token in
                guard let strongSelf = self else { return }

                let xmlHandler = XMLHandler(token: token, assetDefinitionStore: strongSelf.assetDefinitionStore)
                guard xmlHandler.hasAssetDefinition, let server = xmlHandler.server else { return }
                switch server {
                case .any:
                    for each in strongSelf.config.enabledServers {
                        strongSelf.fetchEvents(forTokenContract: token.contractAddress, server: each)
                    }
                case .server(let server):
                    strongSelf.fetchEvents(forTokenContract: token.contractAddress, server: server)
                }
            }.store(in: &cancellable)
    }

    private func fetchEvents(forTokenContract contract: AlphaWallet.Address, server: RPCServer) {
        guard let token = tokensDataStore.token(forContract: contract, server: server) else { return }

        when(resolved: fetchEvents(forToken: token))
            .done { _ in }
            .cauterize()
    }

    private func fetchEvents(forToken token: TokenObject) -> [Promise<Void>] {
        let xmlHandler = XMLHandler(token: token, assetDefinitionStore: assetDefinitionStore)
        guard xmlHandler.hasAssetDefinition else { return [] }
        return xmlHandler.activityCards.compactMap {
            EventSourceCoordinatorForActivities.functional.fetchEvents(config: config, tokenContract: token.contractAddress, server: token.server, card: $0, eventsDataStore: eventsDataStore, queue: queue, wallet: wallet)
        }
    }

    private func fetchEthereumEvents() {
        if rateLimitedUpdater == nil {
            rateLimitedUpdater = RateLimiter(name: "Poll Ethereum events for Activities", limit: 60, autoRun: true) { [weak self] in
                self?.fetchEthereumEventsImpl()
            }
        } else {
            rateLimitedUpdater?.run()
        }
    }

    private func fetchEthereumEventsImpl() {
        guard !isFetching else { return }
        isFetching = true

        let tokens = tokensDataStore.enabledTokenObjects(forServers: enabledServers)
        let promises = tokens.map { fetchEvents(forToken: $0) }.flatMap { $0 }

        when(resolved: promises).done { [weak self] _ in
            self?.isFetching = false
        }
    }
}

extension EventSourceCoordinatorForActivities {
    class functional {}
}

extension EventSourceCoordinatorForActivities.functional {
    static func fetchEvents(config: Config, tokenContract: AlphaWallet.Address, server: RPCServer, card: TokenScriptCard, eventsDataStore: EventsActivityDataStoreProtocol, queue: DispatchQueue, wallet: Wallet) -> Promise<Void> {
        if config.development.isAutoFetchingDisabled {
            return Promise { _ in }
        }

        let (promise, seal) = Promise<Void>.pending()

        let eventOrigin = card.eventOrigin
        let (filterName, filterValue) = eventOrigin.eventFilter
        typealias functional = EventSourceCoordinatorForActivities.functional
        let filterParam = eventOrigin.parameters
            .filter { $0.isIndexed }
            .map { functional.formFilterFrom(fromParameter: $0, filterName: filterName, filterValue: filterValue, wallet: wallet) }

        if filterParam.allSatisfy({ $0 == nil }) {
            //TODO log to console as diagnostic
            seal.fulfill(())
            return promise
        }

        eventsDataStore
            .getLastMatchingEventSortedByBlockNumber(forContract: eventOrigin.contract, tokenContract: tokenContract, server: server, eventName: eventOrigin.eventName)
            .map(on: queue, { oldEvent -> EventFilter in
                let fromBlock: (EventFilter.Block, UInt64)
                if let newestEvent = oldEvent {
                    let value = UInt64(newestEvent.blockNumber + 1)
                    fromBlock = (.blockNumber(value), value)
                } else {
                    fromBlock = (.blockNumber(0), 0)
                }
                let parameterFilters = filterParam.map { $0?.filter }
                let addresses = [EthereumAddress(address: eventOrigin.contract)]
                let toBlock = server.makeMaximumToBlockForEvents(fromBlockNumber: fromBlock.1)
                return EventFilter(fromBlock: fromBlock.0, toBlock: toBlock, addresses: addresses, parameterFilters: parameterFilters)
            }).then(on: queue, { eventFilter in
                getEventLogs(withServer: server, contract: eventOrigin.contract, eventName: eventOrigin.eventName, abiString: eventOrigin.eventAbiString, filter: eventFilter, queue: queue)
            }).then(on: queue, { events -> Promise<[EventActivityInstance]> in
                let promises = events.compactMap { event -> Promise<EventActivityInstance?> in
                    guard let blockNumber = event.eventLog?.blockNumber else {
                        return .value(nil)
                    }

                    return GetBlockTimestampCoordinator()
                        .getBlockTimestamp(blockNumber, onServer: server)
                        .map(on: queue, { date in
                            Self.convertEventToDatabaseObject(event, date: date, filterParam: filterParam, eventOrigin: eventOrigin, tokenContract: tokenContract, server: server)
                        }).recover(on: queue, { _ -> Promise<EventActivityInstance?> in
                            return .value(nil)
                        })
                }

                return when(resolved: promises).map(on: queue, { values -> [EventActivityInstance] in
                    values.compactMap { $0.optionalValue }.compactMap { $0 }
                })
            }).done(on: .main, { events in
                eventsDataStore.add(events: events)
                seal.fulfill(())
            }).catch({ e in
                error(value: e, rpcServer: server, address: tokenContract)
                seal.reject(e)
            })

        return promise
    }

    private static func convertEventToDatabaseObject(_ event: EventParserResultProtocol, date: Date, filterParam: [(filter: [EventFilterable], textEquivalent: String)?], eventOrigin: EventOrigin, tokenContract: AlphaWallet.Address, server: RPCServer) -> EventActivityInstance? {
        guard let eventLog = event.eventLog else { return nil }

        let transactionId = eventLog.transactionHash.hexEncoded
        let decodedResult = EventSourceCoordinator.functional.convertToJsonCompatible(dictionary: event.decodedResult)
        guard let json = decodedResult.jsonString else { return nil }
        //TODO when TokenScript schema allows it, support more than 1 filter
        let filterTextEquivalent = filterParam.compactMap({ $0?.textEquivalent }).first
        let filterText = filterTextEquivalent ?? "\(eventOrigin.eventFilter.name)=\(eventOrigin.eventFilter.value)"

        return EventActivityInstance(contract: eventOrigin.contract, tokenContract: tokenContract, server: server, date: date, eventName: eventOrigin.eventName, blockNumber: Int(eventLog.blockNumber), transactionId: transactionId, transactionIndex: Int(eventLog.transactionIndex), logIndex: Int(eventLog.logIndex), filter: filterText, json: json)
    }

    private static func formFilterFrom(fromParameter parameter: EventParameter, filterName: String, filterValue: String, wallet: Wallet) -> (filter: [EventFilterable], textEquivalent: String)? {
        guard parameter.name == filterName else { return nil }
        guard let parameterType = SolidityType(rawValue: parameter.type) else { return nil }
        let optionalFilter: (filter: AssetAttributeValueUsableAsFunctionArguments, textEquivalent: String)?
        if let implicitAttribute = EventSourceCoordinator.functional.convertToImplicitAttribute(string: filterValue) {
            switch implicitAttribute {
            case .tokenId:
                optionalFilter = nil
            case .ownerAddress:
                optionalFilter = AssetAttributeValueUsableAsFunctionArguments(assetAttribute: .address(wallet.address)).flatMap { (filter: $0, textEquivalent: "\(filterName)=\(wallet.address.eip55String)") }
            case .label, .contractAddress, .symbol:
                optionalFilter = nil
            }
        } else {
            //TODO support things like "$prefix-{tokenId}"
            optionalFilter = nil
        }
        guard let (filterValue, textEquivalent) = optionalFilter else { return nil }
        guard let filterValueTypedForEventFilters = filterValue.coerceToArgumentTypeForEventFilter(parameterType) else { return nil }
        return (filter: [filterValueTypedForEventFilters], textEquivalent: textEquivalent)
    }
}
