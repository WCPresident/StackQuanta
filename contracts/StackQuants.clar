;; Resource Allocation Smart Contract

;; Error Constants
(define-constant CONTRACT_ADMINISTRATOR tx-sender)
(define-constant ERROR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERROR_INVALID_RESOURCE_QUANTITY (err u101))
(define-constant ERROR_INSUFFICIENT_RESOURCE_BALANCE (err u102))
(define-constant ERROR_RESOURCE_TYPE_NOT_FOUND (err u103))
(define-constant ERROR_CONTRACT_ALREADY_INITIALIZED (err u104))
(define-constant ERROR_INVALID_RECIPIENT (err u105))
(define-constant ERROR_RESOURCE_ALLOCATION_EXCEEDED (err u106))
(define-constant ERROR_INSUFFICIENT_PRIORITY (err u107))
(define-constant ERROR_RESOURCE_FROZEN (err u108))
(define-constant ERROR_REQUEST_TIMEOUT (err u109))
(define-constant ERROR_INVALID_PARAMETERS (err u110))

;; Data Variables
(define-data-var contract-initialization-status bool false)
(define-data-var allocation-request-counter uint u0)
(define-data-var resource-system-frozen bool false)
(define-data-var system-under-maintenance bool false)
(define-data-var maximum-resource-allocation-limit uint u1000000)
(define-data-var emergency-administrator-address principal CONTRACT_ADMINISTRATOR)

;; Data Maps
(define-map account-resource-balances principal uint)
(define-map registered-resource-types uint {
    resource-identifier: (string-ascii 64),
    total-resource-supply: uint,
    current-available-supply: uint,
    current-price-per-unit: uint,
    resource-frozen-status: bool,
    required-access-level: uint,
    minimum-allocation-amount: uint,
    maximum-allocation-amount: uint,
    allocation-freeze-period: uint,
    price-update-timestamp: uint
})

(define-map resource-allocation-requests uint {
    requester-address: principal,
    allocation-amount: uint,
    target-resource-type: uint,
    request-current-status: (string-ascii 20),
    requester-priority-level: uint,
    submission-timestamp: uint,
    request-expiration-time: uint,
    allocation-justification: (string-ascii 128)
})

(define-map account-allocation-history principal (list 10 uint))
(define-map resource-historical-prices uint (list 10 uint))
(define-map account-authorization-levels principal (string-ascii 20))
(define-map restricted-accounts principal bool)
(define-map resource-type-dependencies uint (list 5 uint))

;; Private Functions
(define-private (is-contract-administrator)
    (is-eq tx-sender CONTRACT_ADMINISTRATOR)
)

(define-private (is-valid-resource-quantity (requested-quantity uint))
    (and 
        (> requested-quantity u0)
        (<= requested-quantity (var-get maximum-resource-allocation-limit))
    )
)

(define-private (does-resource-type-exist (resource-type-identifier uint))
    (is-some (map-get? registered-resource-types resource-type-identifier))
)

(define-private (is-account-authorized (account-address principal))
    (and
        (not (default-to false (map-get? restricted-accounts account-address)))
        (>= (get-account-priority-level account-address) u1)
    )
)

(define-private (get-account-priority-level (account-address principal))
    (let ((account-role (default-to "USER" (map-get? account-authorization-levels account-address))))
        (if (is-eq account-role "ADMIN")
            u5
            (if (is-eq account-role "PREMIUM")
                u4
                (if (is-eq account-role "BUSINESS")
                    u3
                    (if (is-eq account-role "VERIFIED")
                        u2
                        u1)))))) ;; Default USER level

(define-private (update-price-history (resource-type-identifier uint) (updated-price uint))
    (let (
        (price-history (default-to (list) (map-get? resource-historical-prices resource-type-identifier)))
        (updated-price-history (unwrap! (as-max-len? (concat (list updated-price) price-history) u10) (err u0)))
    )
        (ok (map-set resource-historical-prices resource-type-identifier updated-price-history))
    )
)

(define-private (is-valid-address (account-address principal))
    (is-standard account-address)
)

;; Read Only Functions
(define-read-only (get-account-balance (account-address principal))
    (default-to u0 (map-get? account-resource-balances account-address))
)

(define-read-only (get-resource-details (resource-type-identifier uint))
    (map-get? registered-resource-types resource-type-identifier)
)

(define-read-only (get-allocation-request (request-identifier uint))
    (map-get? resource-allocation-requests request-identifier)
)

(define-read-only (get-account-allocation-history (account-address principal))
    (default-to (list) (map-get? account-allocation-history account-address))
)

(define-read-only (get-resource-price-history (resource-type-identifier uint))
    (default-to (list) (map-get? resource-historical-prices resource-type-identifier))
)

(define-read-only (get-system-status)
    {
        initialized: (var-get contract-initialization-status),
        paused: (var-get resource-system-frozen),
        maintenance: (var-get system-under-maintenance),
        global-limit: (var-get maximum-resource-allocation-limit),
        emergency-contact: (var-get emergency-administrator-address)
    }
)

;; Public Functions
;; System Management Functions
(define-public (initialize-resource-system)
    (begin
        (asserts! (is-contract-administrator) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (not (var-get contract-initialization-status)) ERROR_CONTRACT_ALREADY_INITIALIZED)
        (var-set contract-initialization-status true)
        (var-set allocation-request-counter u0)
        (var-set resource-system-frozen false)
        (var-set system-under-maintenance false)
        (ok true)
    )
)

(define-public (update-system-parameters (new-allocation-limit uint) (new-emergency-admin principal))
    (begin
        (asserts! (is-contract-administrator) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (> new-allocation-limit u0) ERROR_INVALID_PARAMETERS)
        (asserts! (is-valid-address new-emergency-admin) ERROR_INVALID_PARAMETERS)
        (var-set maximum-resource-allocation-limit new-allocation-limit)
        (var-set emergency-administrator-address new-emergency-admin)
        (ok true)
    )
)

;; Resource Management Functions
(define-public (register-resource-type 
    (resource-type-identifier uint) 
    (resource-name (string-ascii 64)) 
    (initial-supply uint) 
    (unit-price uint)
    (min-allocation uint)
    (max-allocation uint)
    (required-priority-level uint))
    (begin
        (asserts! (is-contract-administrator) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (is-valid-resource-quantity initial-supply) ERROR_INVALID_RESOURCE_QUANTITY)
        (asserts! (is-valid-resource-quantity unit-price) ERROR_INVALID_RESOURCE_QUANTITY)
        (asserts! (<= required-priority-level u5) ERROR_INSUFFICIENT_PRIORITY)
        (asserts! (>= min-allocation u1) ERROR_INVALID_PARAMETERS)
        (asserts! (> max-allocation min-allocation) ERROR_INVALID_PARAMETERS)
        (asserts! (<= max-allocation initial-supply) ERROR_INVALID_PARAMETERS)
        (asserts! (not (does-resource-type-exist resource-type-identifier)) ERROR_INVALID_PARAMETERS)
        (asserts! (>= (len resource-name) u1) ERROR_INVALID_PARAMETERS)

        (map-set registered-resource-types resource-type-identifier {
            resource-identifier: resource-name,
            total-resource-supply: initial-supply,
            current-available-supply: initial-supply,
            current-price-per-unit: unit-price,
            resource-frozen-status: false,
            required-access-level: required-priority-level,
            minimum-allocation-amount: min-allocation,
            maximum-allocation-amount: max-allocation,
            allocation-freeze-period: u0,
            price-update-timestamp: block-height
        })
        (ok true)
    )
)
