;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-already-claimed (err u104))
(define-constant insurance-reward-rate u5)
(define-constant base-interest-rate u10)
(define-constant max-interest-rate u25)
(define-constant min-interest-rate u5)
(define-constant extension-fee-rate u15)
(define-constant max-extensions u3)
(define-constant extension-blocks u720)
(define-constant err-max-extensions (err u105))
(define-constant err-extension-not-allowed (err u106))

;; Data Variables
(define-data-var min-credit-score uint u500)
(define-data-var lending-pool uint u0)
(define-data-var insurance-pool uint u0)

;; Data Maps
(define-map users
    principal
    {
        credit-score: uint,
        loans-taken: uint,
        loans-repaid: uint,
        on-time-payments: uint,
        late-payments: uint,
    }
)

(define-map loans
    uint
    {
        borrower: principal,
        amount: uint,
        due-height: uint,
        status: (string-ascii 10),
        insured: bool,
        interest-rate: uint,
        total-amount-due: uint,
        extensions-used: uint,
    }
)

(define-map insurance-contributions
    principal
    {
        amount: uint,
        rewards-earned: uint,
        last-claim-height: uint,
    }
)

(define-map loan-extensions
    uint
    {
        loan-id: uint,
        extensions-count: uint,
        total-extension-fees: uint,
        last-extension-height: uint,
    }
)

;; Public Functions
(define-public (register-user)
    (ok (map-set users tx-sender {
        credit-score: u500,
        loans-taken: u0,
        loans-repaid: u0,
        on-time-payments: u0,
        late-payments: u0,
    }))
)

(define-map loan-counter
    principal
    uint
)

(define-read-only (get-last-loan-id)
    (map-get? loan-counter contract-owner)
)

(define-read-only (calculate-interest-rate (user principal))
    (let (
            (user-data (default-to {
                credit-score: u500,
                loans-taken: u0,
                loans-repaid: u0,
                on-time-payments: u0,
                late-payments: u0,
            }
                (map-get? users user)
            ))
            (total-payments (+ (get on-time-payments user-data) (get late-payments user-data)))
            (payment-ratio (if (> total-payments u0)
                (/ (* (get on-time-payments user-data) u100) total-payments)
                u50
            ))
        )
        (if (> payment-ratio u80)
            min-interest-rate
            (if (< payment-ratio u40)
                max-interest-rate
                (+ min-interest-rate
                    (/
                        (* (- u80 payment-ratio)
                            (- max-interest-rate min-interest-rate)
                        )
                        u40
                    ))
            )
        )
    )
)

(define-public (request-loan (amount uint))
    (let (
            (user-data (unwrap! (map-get? users tx-sender) err-not-found))
            (loan-id (+ (default-to u0 (get-last-loan-id)) u1))
            (interest-rate (calculate-interest-rate tx-sender))
            (total-due (+ amount (/ (* amount interest-rate) u100)))
        )
        (asserts! (>= (get credit-score user-data) (var-get min-credit-score))
            err-invalid-amount
        )
        (map-set loan-counter contract-owner loan-id)
        (map-set users tx-sender
            (merge user-data { loans-taken: (+ (get loans-taken user-data) u1) })
        )
        (ok (map-set loans loan-id {
            borrower: tx-sender,
            amount: amount,
            due-height: (+ burn-block-height u1440),
            status: "ACTIVE",
            insured: false,
            interest-rate: interest-rate,
            total-amount-due: total-due,
            extensions-used: u0,
        }))
    )
)

(define-public (repay-loan (loan-id uint))
    (let (
            (loan (unwrap! (map-get? loans loan-id) err-not-found))
            (user-data (unwrap! (map-get? users tx-sender) err-not-found))
            (is-on-time (<= burn-block-height (get due-height loan)))
            (credit-boost (if is-on-time
                u75
                u25
            ))
        )
        (asserts! (is-eq (get borrower loan) tx-sender) err-owner-only)
        (asserts! (is-eq (get status loan) "ACTIVE") err-invalid-amount)
        (map-set loans loan-id (merge loan { status: "REPAID" }))
        (map-set users tx-sender
            (merge user-data {
                credit-score: (+ (get credit-score user-data) credit-boost),
                loans-repaid: (+ (get loans-repaid user-data) u1),
                on-time-payments: (if is-on-time
                    (+ (get on-time-payments user-data) u1)
                    (get on-time-payments user-data)
                ),
                late-payments: (if is-on-time
                    (get late-payments user-data)
                    (+ (get late-payments user-data) u1)
                ),
            })
        )
        (ok is-on-time)
    )
)

;; Read-Only Functions
(define-read-only (get-user-data (user principal))
    (map-get? users user)
)

(define-read-only (get-loan-data (loan-id uint))
    (map-get? loans loan-id)
)

(define-public (extend-loan (loan-id uint))
    (let (
            (loan (unwrap! (map-get? loans loan-id) err-not-found))
            (extension-data (default-to {
                loan-id: u0,
                extensions-count: u0,
                total-extension-fees: u0,
                last-extension-height: u0,
            }
                (map-get? loan-extensions loan-id)
            ))
            (current-extensions (get extensions-used loan))
            (extension-fee (/ (* (get total-amount-due loan) extension-fee-rate) u100))
        )
        (asserts! (is-eq (get borrower loan) tx-sender) err-owner-only)
        (asserts! (is-eq (get status loan) "ACTIVE") err-invalid-amount)
        (asserts! (< current-extensions max-extensions) err-max-extensions)
        (asserts! (> burn-block-height (- (get due-height loan) u144))
            err-extension-not-allowed
        )

        (map-set loans loan-id
            (merge loan {
                due-height: (+ (get due-height loan) extension-blocks),
                extensions-used: (+ current-extensions u1),
                total-amount-due: (+ (get total-amount-due loan) extension-fee),
            })
        )

        (map-set loan-extensions loan-id {
            loan-id: loan-id,
            extensions-count: (+ (get extensions-count extension-data) u1),
            total-extension-fees: (+ (get total-extension-fees extension-data) extension-fee),
            last-extension-height: burn-block-height,
        })

        (ok extension-fee)
    )
)

(define-public (contribute-to-insurance (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (let ((current-contribution (default-to {
                amount: u0,
                rewards-earned: u0,
                last-claim-height: u0,
            }
                (map-get? insurance-contributions tx-sender)
            )))
            (map-set insurance-contributions tx-sender {
                amount: (+ (get amount current-contribution) amount),
                rewards-earned: (get rewards-earned current-contribution),
                last-claim-height: (get last-claim-height current-contribution),
            })
            (var-set insurance-pool (+ (var-get insurance-pool) amount))
            (ok true)
        )
    )
)

(define-public (insure-loan (loan-id uint))
    (let (
            (loan (unwrap! (map-get? loans loan-id) err-not-found))
            (insurance-cost (/ (get amount loan) u10))
        )
        (asserts! (is-eq (get borrower loan) tx-sender) err-owner-only)
        (asserts! (is-eq (get status loan) "ACTIVE") err-invalid-amount)
        (asserts! (not (get insured loan)) err-already-claimed)
        (asserts! (>= (var-get insurance-pool) (get amount loan))
            err-insufficient-funds
        )
        (map-set loans loan-id (merge loan { insured: true }))
        (ok true)
    )
)

(define-public (claim-insurance (loan-id uint))
    (let (
            (loan (unwrap! (map-get? loans loan-id) err-not-found))
            (user-data (unwrap! (map-get? users tx-sender) err-not-found))
        )
        (asserts! (is-eq (get borrower loan) tx-sender) err-owner-only)
        (asserts! (get insured loan) err-invalid-amount)
        (asserts! (is-eq (get status loan) "ACTIVE") err-already-claimed)
        (asserts! (> burn-block-height (get due-height loan)) err-invalid-amount)
        (map-set loans loan-id (merge loan { status: "DEFAULTED" }))
        (var-set insurance-pool (- (var-get insurance-pool) (get amount loan)))
        (map-set users tx-sender
            (merge user-data { credit-score: (if (>= (get credit-score user-data) u100)
                (- (get credit-score user-data) u100)
                u0
            ) }
            ))
        (ok true)
    )
)

(define-public (claim-rewards)
    (let (
            (contribution (unwrap! (map-get? insurance-contributions tx-sender) err-not-found))
            (blocks-since-last-claim (- burn-block-height (get last-claim-height contribution)))
            (reward-amount (/ (* (get amount contribution) blocks-since-last-claim)
                insurance-reward-rate
            ))
        )
        (asserts! (> blocks-since-last-claim u0) err-invalid-amount)
        (map-set insurance-contributions tx-sender
            (merge contribution {
                rewards-earned: (+ (get rewards-earned contribution) reward-amount),
                last-claim-height: burn-block-height,
            })
        )
        (ok reward-amount)
    )
)

(define-public (withdraw-insurance-contribution (amount uint))
    (let ((contribution (unwrap! (map-get? insurance-contributions tx-sender) err-not-found)))
        (asserts! (<= amount (get amount contribution)) err-insufficient-funds)
        (map-set insurance-contributions tx-sender
            (merge contribution { amount: (- (get amount contribution) amount) })
        )
        (var-set insurance-pool (- (var-get insurance-pool) amount))
        (ok true)
    )
)

(define-read-only (get-insurance-pool-balance)
    (var-get insurance-pool)
)

(define-read-only (get-insurance-contribution (user principal))
    (map-get? insurance-contributions user)
)

(define-read-only (get-payment-history (user principal))
    (match (map-get? users user)
        user-info
        {
            total-payments: (+ (get on-time-payments user-info) (get late-payments user-info)),
            on-time-payments: (get on-time-payments user-info),
            late-payments: (get late-payments user-info),
            payment-ratio: (if (>
                    (+ (get on-time-payments user-info)
                        (get late-payments user-info)
                    )
                    u0
                )
                (/ (* (get on-time-payments user-info) u100)
                    (+ (get on-time-payments user-info)
                        (get late-payments user-info)
                    ))
                u0
            ),
            current-interest-rate: (calculate-interest-rate user),
        }
        {
            total-payments: u0,
            on-time-payments: u0,
            late-payments: u0,
            payment-ratio: u0,
            current-interest-rate: base-interest-rate,
        }
    )
)

(define-read-only (get-extension-data (loan-id uint))
    (map-get? loan-extensions loan-id)
)

(define-read-only (calculate-extension-fee (loan-id uint))
    (match (map-get? loans loan-id)
        loan (some (/ (* (get total-amount-due loan) extension-fee-rate) u100))
        none
    )
)

(define-read-only (can-extend-loan (loan-id uint))
    (match (map-get? loans loan-id)
        loan
        {
            is-active: (is-eq (get status loan) "ACTIVE"),
            extensions-remaining: (- max-extensions (get extensions-used loan)),
            can-extend: (and
                (is-eq (get status loan) "ACTIVE")
                (< (get extensions-used loan) max-extensions)
                (> burn-block-height (- (get due-height loan) u144))
            ),
            extension-fee: (/ (* (get total-amount-due loan) extension-fee-rate) u100),
        }
        {
            is-active: false,
            extensions-remaining: u0,
            can-extend: false,
            extension-fee: u0,
        }
    )
)

;; Admin Functions
(define-public (update-min-credit-score (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set min-credit-score new-score))
    )
)
