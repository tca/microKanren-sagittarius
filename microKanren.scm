;; Jason Hemann and Dan Friedman
;; microKanren, final implementation from paper

;; utilities

(define (assp p l)
  ;; R6RS compatability
  (if (null? l)
      #f
      (if (p (caar l))
	  (car l)
	  (assp p (cdr l)))))

(define (filter p l)
  (if (null? l)
      '()
      (if (p (car l))
	  (cons (car l) (filter p (cdr l)))
	  (filter p (cdr l)))))


;; Variable representation

(define (var c) (vector c))
(define (var? x) (vector? x))
(define (var=? x1 x2) (= (vector-ref x1 0) (vector-ref x2 0)))

(define (ext-s-check x v s)
  (if (occurs-check x v s) #f `((,x . ,v) . ,s)))

(define (walk u s)
  (let ((pr (and (var? u) (assp (lambda (v) (var=? u v)) s))))
    (if pr (walk (cdr pr) s) u)))

(define (occurs-check x v s)
  (let ((v (walk v s)))
    (cond
     ((var? v) (var=? v x))
     ((pair? v) (or (occurs-check x (car v) s)
                    (occurs-check x (cdr v) s)))
     (else #f))))

;; Unification and disequality

(define (unify u v s)
  (let ((u (walk u s)) (v (walk v s)))
    (cond
     ((and (var? u) (var? v) (var=? u v)) s)
     ((var? u) (ext-s-check u v s))
     ((var? v) (ext-s-check v u s))
     ((and (pair? u) (pair? v))
      (let ((s (unify (car u) (car v) s)))
	(and s (unify (cdr u) (cdr v) s))))
     (else (and (eqv? u v) s)))))

(define (subtract-s s^ s)
  ;; This function requires that s^ is some stuff consed onto s
  (if (eq? s^ s)
      '()
      (cons (car s^) (subtract-s (cdr s^) s))))

(define (disequality u v s)
  (let ((s^ (unify u v s)))
    (if s^
	(let ((d (subtract-s s^ s)))
	  (if (null? d) #f d))
	'())))

(define (normalize-disequality-store k)
  ;; the disequality store d is of the form
  ;;      (AND (OR (=/= ...) ...)
  ;;           (OR (=/= ...) ...) ...)
  ;; by de-morgan this can be interpreted as
  ;; (NOT (OR (AND (== ...) ...)
  ;;          (AND (== ...) ...) ...))
  ;; so to normalize we can normalize each
  ;; part of the OR individually (failing if
  ;; any one of them fails), but we need to
  ;; chain each unification in the AND's alt-
  ;; ernatively (and this is what we do here)
  ;; merge them into a single unification op
  (bind (mapm (lambda (es)
		(let ((d^ (disequality (map car es)
				       (map cdr es)
				       (substitution k))))
		  (if d^ (unit d^) mzero)))
	      (filter (lambda (l) (not (null? l)))
		      (disequality-store k)))
	(lambda (d)
	  (unit (make-kanren (counter k) (substitution k) d)))))


;; Monad

(define (unit k) (cons k mzero))
(define (bind $ g)
  (cond
   ((null? $) mzero)
   ((procedure? $) (lambda () (bind ($) g)))
   (else (mplus (g (car $)) (bind (cdr $) g)))))

(define (mapm f l)
  (if (null? l)
      (unit '())
      (bind (f (car l))
	    (lambda (v)
	      (bind (mapm f (cdr l))
		    (lambda (vs)
		      (unit (cons v vs))))))))

(define mzero '())
(define (mplus $1 $2)
  (cond
   ((null? $1) $2)
   ((procedure? $1) (lambda () (mplus $2 ($1))))
   (else (cons (car $1) (mplus (cdr $1) $2)))))


;; the language constructs

(define-record-type <kanren>
  (make-kanren c s d)
  kanren?
  (c counter)
  (s substitution)
  (d disequality-store))

(define empty-state (make-kanren 0 '() '()))

(define (== u v)
  (lambda (k)
    (let ((s (unify u v (substitution k))))
      (if s
	  (normalize-disequality-store
	   (make-kanren (counter k) s (disequality-store k)))
	  mzero))))

(define (=/= u v)
  (lambda (k)
    (let ((d^ (disequality u v (substitution k))))
      (if d^
	  (unit (make-kanren (counter k) (substitution k)
			     (cons d^ (disequality-store k))))
	  mzero))))

(define (call/fresh f)
  (lambda (k)
    (let ((c (counter k)))
      ((f (var c)) (make-kanren (+ 1 c) (substitution k) (disequality-store k))))))

(define (disj g1 g2) (lambda (k) (mplus (g1 k) (g2 k))))
(define (conj g1 g2) (lambda (k) (bind (g1 k) g2)))

