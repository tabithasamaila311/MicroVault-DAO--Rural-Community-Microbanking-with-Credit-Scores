;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))

;; Data Variables
(define-data-var min-credit-score uint u500)
(define-data-var lending-pool uint u0)

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

;; Admin Functions
(define-public (update-min-credit-score (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set min-credit-score new-score))
    )
)
