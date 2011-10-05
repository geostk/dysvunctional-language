(declare (usual-integrations))

;;; The purpose of lifting lets is to increase the scopes of variables
;;; without affecting when and whether their values are computed.
;;; This is useful for common subexpression elimination, because
;;; previously computed expressions remain available longer.

;;; The action of lifting lets is to find LET expressions that occur
;;; in strict contexts and to lift the LET binding outside the
;;; context, but leave the LET body in place.  For example, since the
;;; binding of an outer LET is a strict context, we get
;;;
;;; (let ((x (let ((y 4)) y)))
;;;   x)
;;; ===>
;;; (let ((y 4))
;;;   (let ((x y))
;;;     x))

;;; Lifting lets is safe assuming the program has unique bound names;
;;; if not, it can break because of
;;;
;;; (let ((x 3))
;;;   (let ((y (let ((x 4)) x)))
;;;     x))
;;;
;;; Unfortunately, mere lack of shadowing is not enough, as lifting
;;; lets can introduce shadowing because of
;;;
;;; (let ((x (let ((y 3)) y)))
;;;   (let ((y 4))
;;;     y))

;;; The grammar of a FOL program whose LETs have been lifted is the
;;; same as the normal FOL grammar, except for replacing the
;;; <expression>, <access>, and <construction> nonterminals with the
;;; following:
;;;
;;; expression = <non-let>
;;;            | (let ((<data-var> <non-let>) ...) <expression>)
;;;            | (let-values (((<data-var> <data-var> <data-var> ...) <non-let>))
;;;                <expression>)
;;;
;;; non-let = <data-var> | <number> | <boolean> | ()
;;;         | (if <non-let> <expression> <expression>)
;;;         | (lambda (<data-var>) <expression>)  ; for escape only
;;;         | <access>
;;;         | <construction>
;;;         | (values <non-let> <non-let> <non-let> ...)
;;;         | (<proc-var> <non-let> ...)
;;;
;;; access = (car <non-let>)
;;;        | (cdr <non-let>)
;;;        | (vector-ref <non-let> <integer>)
;;;
;;; construction = (cons <non-let> <non-let>)
;;;              | (vector <non-let> ...)

;;; TODO Describe the algorithm.

(define (%lift-lets program)
  (if (begin-form? program)
      `(begin
         ,@(map lift-lets-definition (except-last-pair (cdr program)))
         ,(lift-lets-expression (last program)))
      (lift-lets-expression program)))

(define lift-lets-definition
  (rule `(define (? formals)
           (argument-types (?? stuff))
           (? body))
        `(define ,formals
           (argument-types ,@stuff)
           ,(lift-lets-expression body))))

(define (lift-lets-expression expr)
  ;; This is written in continuation passing style because the
  ;; recursive call returns two things: the rewritten expression, and
  ;; the list of bindings that this expression seeks to introduce.
  ;; The bindings lists are represented as functions that will wrap a
  ;; given expression in that binding list, for fast appending.
  (define null (lambda (expr) expr))
  (define (singleton var exp)
    (lambda (expr)
      `(let ((,var ,exp))
         ,expr)))
  (define (values-singleton names exp)
    (lambda (expr)
      `(let-values ((,names ,exp))
         ,expr)))
  (define (append lst1 lst2)
    (lambda (expr)
      (lst1 (lst2 expr))))
  (define (build expr lst)
    (lst expr))
  (define (loop expr win)
    (cond ((or (fol-var? expr)
               (fol-const? expr))
           (win expr null))
          ((if-form? expr)
           (lift-lets-from-if expr win))
          ((let-form? expr)
           (lift-lets-from-let expr win))
          ((let-values-form? expr)
           (lift-lets-from-let-values expr win))
          ((lambda-form? expr)
           (lift-lets-from-lambda expr win))
          (else ;; general application
           (lift-lets-from-application expr win))))
  (define (lift-lets-from-if expr win)
    (let ((predicate (cadr expr))
          (consequent (caddr expr))
          (alternate (cadddr expr)))
      (loop predicate
            (lambda (new-pred pred-binds)
              (win `(if ,new-pred
                        ,(lift-lets-expression consequent)
                        ,(lift-lets-expression alternate))
                   pred-binds)))))
  (define (lift-lets-from-let expr win)
    (let ((body (caddr expr)))
      (let per-binding ((bindings (cadr expr))
                        (done null))
        (if (null? bindings)
            (loop body (lambda (new-body body-binds)
                         (win new-body (append done body-binds))))
            (let ((binding (car bindings)))
              (loop (cadr binding)
                    (lambda (new-exp exp-binds)
                      (per-binding
                       (cdr bindings)
                       (append done
                               (append exp-binds
                                       (singleton
                                        (car binding) new-exp)))))))))))
  (define (lift-lets-from-let-values expr win)
    ;; TODO Abstract the commonalities with LET forms?
    (let ((binding (caadr expr))
          (body (caddr expr)))
      (let ((names (car binding))
            (sub-exp (cadr binding)))
        (loop sub-exp
         (lambda (new-sub-expr sub-exp-binds)
           (loop body
            (lambda (new-body body-binds)
              (win new-body
                   (append sub-exp-binds
                           (append (values-singleton names new-sub-expr)
                                   body-binds))))))))))
  (define (lift-lets-from-lambda expr win)
    (win `(lambda ,(cadr expr)
            ,(lift-lets-expression (caddr expr)))
         null))
  (define (lift-lets-from-application expr win)
    ;; In ANF, anything that looks like an application can't have
    ;; nested LETs.
    (win expr null))
  (loop expr build))

(define (lets-lifted? expr)
  (equal? expr (%lift-lets expr)))