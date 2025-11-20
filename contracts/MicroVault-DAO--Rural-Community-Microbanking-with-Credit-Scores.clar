;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))

;; Community Savings Groups (Chama) Constants
(define-constant err-group-not-found (err u107))
(define-constant err-already-member (err u108))
(define-constant err-insufficient-contribution (err u109))
(define-constant err-not-eligible-for-disbursement (err u110))
(define-constant err-goal-not-set (err u111))
(define-constant err-unauthorized-action (err u112))
(define-constant err-already-claimed (err u113))
(define-constant err-insufficient-pool (err u114))
(define-constant min-group-size u3)
(define-constant max-group-size u20)
(define-constant min-contribution u100)
(define-constant group-interest-rate u2)
(define-constant disbursement-blocks u4320)
(define-constant goal-completion-bonus u50)

;; Data Variables
(define-data-var min-credit-score uint u500)
(define-data-var lending-pool uint u0)

;; Community Savings Groups Data Variables
(define-data-var next-group-id uint u1)
(define-data-var total-savings-pool uint u0)

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

;; Community Savings Groups Maps
(define-map savings-groups
    uint
    {
        creator: principal,
        name: (string-ascii 50),
        description: (string-ascii 200),
        member-count: uint,
        total-contributions: uint,
        created-at: uint,
        is-active: bool,
        contribution-frequency: uint,
        disbursement-order: (list 20 principal),
        current-disbursement-index: uint,
    }
)

(define-map group-members
    {
        group-id: uint,
        member: principal,
    }
    {
        total-contributed: uint,
        contributions-count: uint,
        last-contribution-height: uint,
        disbursement-received: uint,
        join-height: uint,
        reputation-score: uint,
    }
)

(define-map group-goals
    uint
    {
        target-amount: uint,
        deadline: uint,
        achieved: bool,
        achievement-height: uint,
        bonus-distributed: bool,
    }
)

(define-map member-reputation
    principal
    {
        total-groups: uint,
        successful-contributions: uint,
        failed-contributions: uint,
        average-score: uint,
        last-updated: uint,
    }
)

(define-map pool-contributors
    principal
    {
        total-funded: uint,
        total-withdrawn: uint,
        last-fund-height: uint,
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

;; Community Savings Groups Functions
(define-public (create-savings-group
        (name (string-ascii 50))
        (description (string-ascii 200))
        (contribution-frequency uint)
    )
    (let ((group-id (var-get next-group-id)))
        (asserts! (> contribution-frequency u0) err-invalid-amount)
        (map-set savings-groups group-id {
            creator: tx-sender,
            name: name,
            description: description,
            member-count: u1,
            total-contributions: u0,
            created-at: burn-block-height,
            is-active: true,
            contribution-frequency: contribution-frequency,
            disbursement-order: (list tx-sender),
            current-disbursement-index: u0,
        })
        (map-set group-members {
            group-id: group-id,
            member: tx-sender,
        } {
            total-contributed: u0,
            contributions-count: u0,
            last-contribution-height: u0,
            disbursement-received: u0,
            join-height: burn-block-height,
            reputation-score: u100,
        })
        (var-set next-group-id (+ group-id u1))
        (ok group-id)
    )
)

(define-public (join-group
        (group-id uint)
        (initial-contribution uint)
    )
    (let (
            (group (unwrap! (map-get? savings-groups group-id) err-group-not-found))
            (member-key {
                group-id: group-id,
                member: tx-sender,
            })
        )
        (asserts! (get is-active group) err-unauthorized-action)
        (asserts! (< (get member-count group) max-group-size)
            err-unauthorized-action
        )
        (asserts! (>= initial-contribution min-contribution)
            err-insufficient-contribution
        )
        (asserts! (is-none (map-get? group-members member-key))
            err-already-member
        )

        (map-set group-members member-key {
            total-contributed: initial-contribution,
            contributions-count: u1,
            last-contribution-height: burn-block-height,
            disbursement-received: u0,
            join-height: burn-block-height,
            reputation-score: u100,
        })

        (map-set savings-groups group-id
            (merge group {
                member-count: (+ (get member-count group) u1),
                total-contributions: (+ (get total-contributions group) initial-contribution),
                disbursement-order: (unwrap!
                    (as-max-len?
                        (append (get disbursement-order group) tx-sender)
                        u20
                    )
                    err-unauthorized-action
                ),
            })
        )

        (var-set total-savings-pool
            (+ (var-get total-savings-pool) initial-contribution)
        )
        (ok true)
    )
)

(define-public (make-contribution
        (group-id uint)
        (amount uint)
    )
    (let (
            (group (unwrap! (map-get? savings-groups group-id) err-group-not-found))
            (member-key {
                group-id: group-id,
                member: tx-sender,
            })
            (member-data (unwrap! (map-get? group-members member-key) err-not-found))
        )
        (asserts! (get is-active group) err-unauthorized-action)
        (asserts! (>= amount min-contribution) err-insufficient-contribution)

        (map-set group-members member-key
            (merge member-data {
                total-contributed: (+ (get total-contributed member-data) amount),
                contributions-count: (+ (get contributions-count member-data) u1),
                last-contribution-height: burn-block-height,
                reputation-score: (if (<= (+ (get reputation-score member-data) u10) u200)
                    (+ (get reputation-score member-data) u10)
                    u200
                ),
            })
        )

        (map-set savings-groups group-id
            (merge group { total-contributions: (+ (get total-contributions group) amount) })
        )

        (var-set total-savings-pool (+ (var-get total-savings-pool) amount))
        (ok true)
    )
)

(define-public (request-disbursement (group-id uint))
    (let (
            (group (unwrap! (map-get? savings-groups group-id) err-group-not-found))
            (member-key {
                group-id: group-id,
                member: tx-sender,
            })
            (member-data (unwrap! (map-get? group-members member-key) err-not-found))
            (disbursement-list (get disbursement-order group))
            (current-index (get current-disbursement-index group))
            (eligible-member (unwrap! (element-at disbursement-list current-index)
                err-not-eligible-for-disbursement
            ))
            (disbursement-amount (/ (get total-contributions group) (get member-count group)))
        )
        (asserts! (get is-active group) err-unauthorized-action)
        (asserts! (is-eq tx-sender eligible-member)
            err-not-eligible-for-disbursement
        )
        (asserts! (>= (get member-count group) min-group-size)
            err-unauthorized-action
        )
        (asserts! (is-eq (get disbursement-received member-data) u0)
            err-already-claimed
        )

        (map-set group-members member-key
            (merge member-data { disbursement-received: disbursement-amount })
        )

        (map-set savings-groups group-id
            (merge group { current-disbursement-index: (+ current-index u1) })
        )

        (var-set total-savings-pool
            (- (var-get total-savings-pool) disbursement-amount)
        )
        (ok disbursement-amount)
    )
)

(define-public (set-group-goal
        (group-id uint)
        (target-amount uint)
        (deadline uint)
    )
    (let ((group (unwrap! (map-get? savings-groups group-id) err-group-not-found)))
        (asserts! (is-eq tx-sender (get creator group)) err-unauthorized-action)
        (asserts! (> target-amount u0) err-invalid-amount)
        (asserts! (> deadline burn-block-height) err-invalid-amount)

        (map-set group-goals group-id {
            target-amount: target-amount,
            deadline: deadline,
            achieved: false,
            achievement-height: u0,
            bonus-distributed: false,
        })
        (ok true)
    )
)

(define-public (check-goal-achievement (group-id uint))
    (let (
            (group (unwrap! (map-get? savings-groups group-id) err-group-not-found))
            (goal (unwrap! (map-get? group-goals group-id) err-goal-not-set))
        )
        (asserts! (not (get achieved goal)) err-already-claimed)
        (asserts! (>= (get total-contributions group) (get target-amount goal))
            err-insufficient-contribution
        )

        (map-set group-goals group-id
            (merge goal {
                achieved: true,
                achievement-height: burn-block-height,
            })
        )
        (ok true)
    )
)

;; Read-Only Functions for Community Savings Groups
(define-read-only (get-group-data (group-id uint))
    (map-get? savings-groups group-id)
)

(define-read-only (get-group-member-data
        (group-id uint)
        (member principal)
    )
    (map-get? group-members {
        group-id: group-id,
        member: member,
    })
)

(define-read-only (get-group-goal (group-id uint))
    (map-get? group-goals group-id)
)

(define-read-only (get-member-reputation (member principal))
    (map-get? member-reputation member)
)

(define-read-only (calculate-group-interest (group-id uint))
    (match (map-get? savings-groups group-id)
        group (let (
                (base-interest (/ (* (get total-contributions group) group-interest-rate) u100))
                (member-bonus (/ (* (get member-count group) u10) u100))
            )
            (some (+ base-interest member-bonus))
        )
        none
    )
)

(define-read-only (get-next-disbursement-recipient (group-id uint))
    (match (map-get? savings-groups group-id)
        group (let (
                (disbursement-list (get disbursement-order group))
                (current-index (get current-disbursement-index group))
            )
            (element-at disbursement-list current-index)
        )
        none
    )
)

;; Admin Functions
(define-public (update-min-credit-score (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set min-credit-score new-score))
    )
)

(define-read-only (get-lending-pool)
    (var-get lending-pool)
)

(define-read-only (get-pool-contributor (contributor principal))
    (map-get? pool-contributors contributor)
)

(define-read-only (get-contributor-available-pool (contributor principal))
    (match (map-get? pool-contributors contributor)
        contributor-data (let ((available (- (get total-funded contributor-data)
                (get total-withdrawn contributor-data)
            )))
            (some available)
        )
        none
    )
)

(define-public (fund-lending-pool (amount uint))
    (let ((existing (map-get? pool-contributors tx-sender)))
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (var-set lending-pool (+ (var-get lending-pool) amount))
            (if (is-some existing)
                (let ((contributor (unwrap! existing err-not-found)))
                    (map-set pool-contributors tx-sender {
                        total-funded: (+ (get total-funded contributor) amount),
                        total-withdrawn: (get total-withdrawn contributor),
                        last-fund-height: burn-block-height,
                    })
                )
                (map-set pool-contributors tx-sender {
                    total-funded: amount,
                    total-withdrawn: u0,
                    last-fund-height: burn-block-height,
                })
            )
            (ok (var-get lending-pool))
        )
    )
)

(define-public (withdraw-from-pool (amount uint))
    (let (
            (contributor-data (unwrap! (map-get? pool-contributors tx-sender) err-not-found))
            (available (- (get total-funded contributor-data)
                (get total-withdrawn contributor-data)
            ))
        )
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (>= available amount) err-insufficient-pool)
            (asserts! (>= (var-get lending-pool) amount) err-insufficient-pool)
            (map-set pool-contributors tx-sender {
                total-funded: (get total-funded contributor-data),
                total-withdrawn: (+ (get total-withdrawn contributor-data) amount),
                last-fund-height: (get last-fund-height contributor-data),
            })
            (var-set lending-pool (- (var-get lending-pool) amount))
            (ok amount)
        )
    )
)
