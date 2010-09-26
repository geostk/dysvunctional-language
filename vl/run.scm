(define (start-vl)
  (initialize-vl-user-env)
  (run-vl))

(define (run-vl)
  (display "vl > ")
  (let ((answer (concrete-eval (macroexpand (read)) vl-user-env)))
    (display "; vl value: ")
    (write answer)
    (newline))
  (run-vl))

(define (vl-eval form)
  (initialize-vl-user-env)
  (concrete-eval (macroexpand form) vl-user-env))