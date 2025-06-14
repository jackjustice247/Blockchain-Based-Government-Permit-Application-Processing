;; Application Submission Contract
;; Manages permit application submissions and lifecycle

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-application-not-found (err u101))
(define-constant err-invalid-data (err u102))
(define-constant err-agency-not-verified (err u103))
(define-constant err-application-already-exists (err u104))
(define-constant err-invalid-status-transition (err u105))

;; Status constants
(define-constant status-submitted "submitted")
(define-constant status-under-review "under-review")
(define-constant status-approved "approved")
(define-constant status-rejected "rejected")
(define-constant status-cancelled "cancelled")

;; Data Variables
(define-data-var next-application-id uint u1)

;; Data Maps
(define-map applications
  uint
  {
    id: uint,
    applicant: principal,
    agency: principal,
    permit-type: (string-ascii 50),
    status: (string-ascii 20),
    submission-date: uint,
    last-updated: uint,
    data: (string-ascii 500),
    documents-hash: (buff 32),
    fee-paid: uint,
    priority: (string-ascii 10)
  }
)

(define-map user-applications
  {user: principal, index: uint}
  uint
)

(define-map user-application-count
  principal
  uint
)

(define-map application-updates
  {application-id: uint, update-id: uint}
  {
    updated-by: principal,
    update-date: uint,
    field: (string-ascii 20),
    old-value: (string-ascii 100),
    new-value: (string-ascii 100),
    notes: (string-ascii 200)
  }
)

(define-map application-update-count
  uint
  uint
)

;; Private Functions
(define-private (is-valid-permit-type (permit-type (string-ascii 50)))
  (> (len permit-type) u0)
)

(define-private (is-valid-application-data (data (string-ascii 500)))
  (> (len data) u0)
)

(define-private (is-valid-status-transition (current-status (string-ascii 20)) (new-status (string-ascii 20)))
  (or
    ;; From submitted
    (and (is-eq current-status status-submitted)
         (or (is-eq new-status status-under-review)
             (is-eq new-status status-cancelled)))
    ;; From under-review
    (and (is-eq current-status status-under-review)
         (or (is-eq new-status status-approved)
             (is-eq new-status status-rejected)
             (is-eq new-status status-submitted)))
    ;; From approved (limited transitions)
    (and (is-eq current-status status-approved)
         (is-eq new-status status-cancelled))
    ;; From rejected
    (and (is-eq current-status status-rejected)
         (is-eq new-status status-submitted))
  )
)

(define-private (get-agency-verification-contract)
  .government-agency-verification
)

(define-private (increment-user-application-count (user principal))
  (let
    (
      (current-count (default-to u0 (map-get? user-application-count user)))
    )
    (map-set user-application-count user (+ current-count u1))
    (+ current-count u1)
  )
)

;; Public Functions

;; Submit a new permit application
(define-public (submit-application
  (agency principal)
  (permit-type (string-ascii 50))
  (data (string-ascii 500))
  (documents-hash (buff 32))
  (fee-paid uint))
  (let
    (
      (application-id (var-get next-application-id))
      (current-block-height block-height)
      (user-index (increment-user-application-count tx-sender))
    )
    ;; Validate inputs
    (asserts! (is-valid-permit-type permit-type) err-invalid-data)
    (asserts! (is-valid-application-data data) err-invalid-data)

    ;; Verify agency is active (this would call the agency verification contract)
    ;; For now, we'll assume agency verification is handled externally

    ;; Create application
    (map-set applications application-id
      {
        id: application-id,
        applicant: tx-sender,
        agency: agency,
        permit-type: permit-type,
        status: status-submitted,
        submission-date: current-block-height,
        last-updated: current-block-height,
        data: data,
        documents-hash: documents-hash,
        fee-paid: fee-paid,
        priority: "normal"
      }
    )

    ;; Track user applications
    (map-set user-applications {user: tx-sender, index: (- user-index u1)} application-id)

    ;; Initialize update count
    (map-set application-update-count application-id u0)

    ;; Increment next ID
    (var-set next-application-id (+ application-id u1))

    (print {
      event: "application-submitted",
      application-id: application-id,
      applicant: tx-sender,
      agency: agency,
      permit-type: permit-type
    })
    (ok application-id)
  )
)

;; Update application status
(define-public (update-application-status (application-id uint) (new-status (string-ascii 20)) (notes (string-ascii 200)))
  (let
    (
      (application (unwrap! (map-get? applications application-id) err-application-not-found))
      (current-status (get status application))
      (update-id (default-to u0 (map-get? application-update-count application-id)))
    )
    ;; Only agency or contract owner can update status
    (asserts! (or (is-eq tx-sender (get agency application)) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (is-valid-status-transition current-status new-status) err-invalid-status-transition)

    ;; Update application
    (map-set applications application-id
      (merge application {
        status: new-status,
        last-updated: block-height
      })
    )

    ;; Record update history
    (map-set application-updates {application-id: application-id, update-id: update-id}
      {
        updated-by: tx-sender,
        update-date: block-height,
        field: "status",
        old-value: current-status,
        new-value: new-status,
        notes: notes
      }
    )

    (map-set application-update-count application-id (+ update-id u1))

    (print {
      event: "application-status-updated",
      application-id: application-id,
      old-status: current-status,
      new-status: new-status,
      updated-by: tx-sender
    })
    (ok true)
  )
)

;; Update application data
(define-public (update-application-data (application-id uint) (new-data (string-ascii 500)) (new-documents-hash (buff 32)))
  (let
    (
      (application (unwrap! (map-get? applications application-id) err-application-not-found))
      (current-status (get status application))
    )
    ;; Only applicant can update data, and only if not yet approved
    (asserts! (is-eq tx-sender (get applicant application)) err-unauthorized)
    (asserts! (not (is-eq current-status status-approved)) err-invalid-status-transition)
    (asserts! (is-valid-application-data new-data) err-invalid-data)

    (map-set applications application-id
      (merge application {
        data: new-data,
        documents-hash: new-documents-hash,
        last-updated: block-height
      })
    )

    (print {
      event: "application-data-updated",
      application-id: application-id,
      applicant: tx-sender
    })
    (ok true)
  )
)

;; Set application priority
(define-public (set-application-priority (application-id uint) (priority (string-ascii 10)))
  (let
    (
      (application (unwrap! (map-get? applications application-id) err-application-not-found))
    )
    (asserts! (or (is-eq tx-sender (get agency application)) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (or (is-eq priority "low") (is-eq priority "normal") (is-eq priority "high") (is-eq priority "urgent")) err-invalid-data)

    (map-set applications application-id
      (merge application {
        priority: priority,
        last-updated: block-height
      })
    )

    (print {
      event: "application-priority-updated",
      application-id: application-id,
      priority: priority
    })
    (ok true)
  )
)

;; Cancel application
(define-public (cancel-application (application-id uint) (reason (string-ascii 200)))
  (let
    (
      (application (unwrap! (map-get? applications application-id) err-application-not-found))
      (current-status (get status application))
    )
    ;; Only applicant can cancel their own application
    (asserts! (is-eq tx-sender (get applicant application)) err-unauthorized)
    (asserts! (not (is-eq current-status status-approved)) err-invalid-status-transition)

    (map-set applications application-id
      (merge application {
        status: status-cancelled,
        last-updated: block-height
      })
    )

    (print {
      event: "application-cancelled",
      application-id: application-id,
      reason: reason
    })
    (ok true)
  )
)

;; Read-only Functions

;; Get application details
(define-read-only (get-application (application-id uint))
  (map-get? applications application-id)
)

;; Get applications by user
(define-read-only (get-user-application (user principal) (index uint))
  (map-get? user-applications {user: user, index: index})
)

;; Get user application count
(define-read-only (get-user-application-count (user principal))
  (default-to u0 (map-get? user-application-count user))
)

;; Get application status
(define-read-only (get-application-status (application-id uint))
  (match (map-get? applications application-id)
    application (some (get status application))
    none
  )
)

;; Get applications by agency
(define-read-only (get-applications-by-agency (agency principal))
  ;; This would require additional indexing in a production system
  ;; For now, returning a simple response
  (ok "Use off-chain indexing for efficient agency queries")
)

;; Get next application ID
(define-read-only (get-next-application-id)
  (var-get next-application-id)
)

;; Get application update history
(define-read-only (get-application-update (application-id uint) (update-id uint))
  (map-get? application-updates {application-id: application-id, update-id: update-id})
)

;; Get application update count
(define-read-only (get-application-update-count (application-id uint))
  (default-to u0 (map-get? application-update-count application-id))
)

;; Check if application exists
(define-read-only (application-exists (application-id uint))
  (is-some (map-get? applications application-id))
)
