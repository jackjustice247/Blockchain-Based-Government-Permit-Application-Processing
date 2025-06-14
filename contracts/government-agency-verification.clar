;; Government Agency Verification Contract
;; Manages registration and verification of government agencies

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-agency-not-found (err u101))
(define-constant err-agency-already-exists (err u102))
(define-constant err-invalid-data (err u103))

;; Data Variables
(define-data-var next-agency-id uint u1)

;; Data Maps
(define-map agencies
  principal
  {
    id: uint,
    name: (string-ascii 100),
    jurisdiction: (string-ascii 50),
    status: (string-ascii 20),
    registration-date: uint,
    contact-info: (string-ascii 200),
    registered-by: principal
  }
)

(define-map agency-admins
  principal
  bool
)

;; Initialize contract owner as admin
(map-set agency-admins contract-owner true)

;; Private Functions
(define-private (is-admin (user principal))
  (default-to false (map-get? agency-admins user))
)

(define-private (is-valid-agency-data (name (string-ascii 100)) (jurisdiction (string-ascii 50)) (contact (string-ascii 200)))
  (and
    (> (len name) u0)
    (> (len jurisdiction) u0)
    (> (len contact) u0)
  )
)

;; Public Functions

;; Register a new government agency
(define-public (register-agency (agency principal) (name (string-ascii 100)) (jurisdiction (string-ascii 50)) (contact-info (string-ascii 200)))
  (let
    (
      (agency-id (var-get next-agency-id))
      (current-block-height block-height)
    )
    (asserts! (is-admin tx-sender) err-unauthorized)
    (asserts! (is-none (map-get? agencies agency)) err-agency-already-exists)
    (asserts! (is-valid-agency-data name jurisdiction contact-info) err-invalid-data)

    (map-set agencies agency
      {
        id: agency-id,
        name: name,
        jurisdiction: jurisdiction,
        status: "active",
        registration-date: current-block-height,
        contact-info: contact-info,
        registered-by: tx-sender
      }
    )
    (var-set next-agency-id (+ agency-id u1))
    (print {event: "agency-registered", agency: agency, id: agency-id})
    (ok agency-id)
  )
)

;; Verify if an agency is registered and active
(define-public (verify-agency (agency principal))
  (match (map-get? agencies agency)
    agency-data (ok (is-eq (get status agency-data) "active"))
    (err err-agency-not-found)
  )
)

;; Update agency status
(define-public (update-agency-status (agency principal) (new-status (string-ascii 20)))
  (let
    (
      (agency-data (unwrap! (map-get? agencies agency) err-agency-not-found))
    )
    (asserts! (is-admin tx-sender) err-unauthorized)
    (asserts! (or (is-eq new-status "active") (is-eq new-status "suspended") (is-eq new-status "inactive")) err-invalid-data)

    (map-set agencies agency
      (merge agency-data {status: new-status})
    )
    (print {event: "agency-status-updated", agency: agency, status: new-status})
    (ok true)
  )
)

;; Add agency admin
(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (is-admin tx-sender) err-unauthorized)
    (map-set agency-admins new-admin true)
    (print {event: "admin-added", admin: new-admin})
    (ok true)
  )
)

;; Remove agency admin
(define-public (remove-admin (admin principal))
  (begin
    (asserts! (is-admin tx-sender) err-unauthorized)
    (asserts! (not (is-eq admin contract-owner)) err-unauthorized)
    (map-delete agency-admins admin)
    (print {event: "admin-removed", admin: admin})
    (ok true)
  )
)

;; Update agency information
(define-public (update-agency-info (agency principal) (name (string-ascii 100)) (jurisdiction (string-ascii 50)) (contact-info (string-ascii 200)))
  (let
    (
      (agency-data (unwrap! (map-get? agencies agency) err-agency-not-found))
    )
    (asserts! (is-admin tx-sender) err-unauthorized)
    (asserts! (is-valid-agency-data name jurisdiction contact-info) err-invalid-data)

    (map-set agencies agency
      (merge agency-data {
        name: name,
        jurisdiction: jurisdiction,
        contact-info: contact-info
      })
    )
    (print {event: "agency-info-updated", agency: agency})
    (ok true)
  )
)

;; Read-only Functions

;; Get agency information
(define-read-only (get-agency-info (agency principal))
  (map-get? agencies agency)
)

;; Check if user is admin
(define-read-only (is-agency-admin (user principal))
  (is-admin user)
)

;; Check if agency is active
(define-read-only (is-agency-active (agency principal))
  (match (map-get? agencies agency)
    agency-data (is-eq (get status agency-data) "active")
    false
  )
)

;; Get next agency ID
(define-read-only (get-next-agency-id)
  (var-get next-agency-id)
)

;; Get agency status
(define-read-only (get-agency-status (agency principal))
  (match (map-get? agencies agency)
    agency-data (some (get status agency-data))
    none
  )
)
