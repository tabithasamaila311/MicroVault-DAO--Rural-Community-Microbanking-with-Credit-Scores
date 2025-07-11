;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-already-claimed (err u104))
(define-constant insurance-reward-rate u5)

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

;; Public Functions
(define-public (register-user)
    (ok (map-set users tx-sender {
        credit-score: u500,
        loans-taken: u0,
        loans-repaid: u0,
    }))
)

(define-map loan-counter
    principal
    uint
)

(define-read-only (get-last-loan-id)
    (map-get? loan-counter contract-owner)
)

(define-public (request-loan (amount uint))
    (let (
            (user-data (unwrap! (map-get? users tx-sender) err-not-found))
            (loan-id (+ (default-to u0 (get-last-loan-id)) u1))
        )
        (asserts! (>= (get credit-score user-data) (var-get min-credit-score))
            err-invalid-amount
        )
        (map-set loan-counter contract-owner loan-id)
        (ok (map-set loans loan-id {
            borrower: tx-sender,
            amount: amount,
            due-height: (+ burn-block-height u1440),
            status: "ACTIVE",
            insured: false,
        }))
    )
)

(define-public (repay-loan (loan-id uint))
    (let (
            (loan (unwrap! (map-get? loans loan-id) err-not-found))
            (user-data (unwrap! (map-get? users tx-sender) err-not-found))
        )
        (asserts! (is-eq (get borrower loan) tx-sender) err-owner-only)
        (map-set loans loan-id (merge loan { status: "REPAID" }))
        (map-set users tx-sender
            (merge user-data {
                credit-score: (+ (get credit-score user-data) u50),
                loans-repaid: (+ (get loans-repaid user-data) u1),
            })
        )
        (ok true)
    )
)

;; Read-Only Functions
(define-read-only (get-user-data (user principal))
    (map-get? users user)
)

(define-read-only (get-loan-data (loan-id uint))
    (map-get? loans loan-id)
)

(define-public (contribute-to-insurance (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (let (
                (current-contribution (default-to { amount: u0, rewards-earned: u0, last-claim-height: u0 }
                    (map-get? insurance-contributions tx-sender)))
            )
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
        (asserts! (>= (var-get insurance-pool) (get amount loan)) err-insufficient-funds)
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
            (merge user-data {
                credit-score: (if (>= (get credit-score user-data) u100) 
                    (- (get credit-score user-data) u100) 
                    u0),
            })
        )
        (ok true)
    )
)

(define-public (claim-rewards)
    (let (
            (contribution (unwrap! (map-get? insurance-contributions tx-sender) err-not-found))
            (blocks-since-last-claim (- burn-block-height (get last-claim-height contribution)))
            (reward-amount (/ (* (get amount contribution) blocks-since-last-claim) insurance-reward-rate))
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
    (let (
            (contribution (unwrap! (map-get? insurance-contributions tx-sender) err-not-found))
        )
        (asserts! (<= amount (get amount contribution)) err-insufficient-funds)
        (map-set insurance-contributions tx-sender
            (merge contribution {
                amount: (- (get amount contribution) amount),
            })
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

;; Admin Functions
(define-public (update-min-credit-score (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set min-credit-score new-score))
    )
)
