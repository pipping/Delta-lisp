;; -*- mode:common-lisp; indent-tabs-mode: nil -*-

(defpackage #:delta-lisp
  (:export #:delta-file)
  (:use #:cl #:external-program))

(in-package #:delta-lisp)

;; TODO: parallelise run-on-input invocations

;; FIXME: verify that initial version passes.

;; FIXME: splits by newline at this point already

(defvar *seen-args* nil)

;; Debugging
(defvar *unique-calls* 0)
(defvar *duplicate-calls* 0)

(defun file->annotated-strings (filename)
  (let (buf)
    (with-open-file (stream filename)
      (loop for line = (read-line stream nil 'end)
            for i = 0 then (1+ i)
            until (eq line 'end)
            do (push (cons line i) buf)))
    (reverse buf)))

(defun annotated-strings->string (list)
  (format nil "~{~a~%~}" (map 'list #'car list)))

(defun annotated-strings->file (input)
  (with-open-file (stream "output" :direction :output :if-exists :supersede)
    (format stream "~a" (annotated-strings->string input))))

(defun extract-indices (input)
  (map 'list #'cdr input))

(defun run-on-input (input)
  (let ((original-indices (extract-indices input)))
    (format t "Calling program on original lines: ~a~%" original-indices)
    (or (and (member original-indices *seen-args* :test #'equal)
             (incf *duplicate-calls*)
             nil)
        (progn
          (incf *unique-calls*)
          (push original-indices *seen-args*)
          (annotated-strings->file input)
          (multiple-value-bind (status return-code) (external-program:run "./test.sh" '("output"))
            (declare (ignore status))
            (= 0 return-code))))))

(defun compute-breaks (length parts)
  (do ((i 0 (1+ i))
       (breaks nil (cons (floor (* i (/ length parts))) breaks)))
      ((>= i parts) (reverse breaks))))

(defun test-subsets (list-of-subsets input)
  (loop for los = list-of-subsets then (cdr los)
        while los
        for subset = (apply #'subseq input (list (first los) (second los)))
        do (when (run-on-input subset)
             (return subset))))

(defun test-complements (list-of-subsets input)
  (when (cddr list-of-subsets) ; Minor optimization as long as there is no caching
    (loop for los = list-of-subsets then (cdr los)
          while los
          for begin = (first los)
          for end = (second los)
          for complement = (append (subseq input 0 begin)
                                   (and end (subseq input end)))
          do (when (run-on-input complement)
               (return complement)))))

(defun delta (input)
  (labels ((ddmin (list parts check-subsets)
             (let ((breaks (compute-breaks (length list) parts)))
               (or
                ;; check if a subset fails
                (and check-subsets
                     (let ((subset (test-subsets breaks list)))
                       (and subset (progn (format t "Subset: ~{~a~^, ~}~%" (map 'list #'car subset)) ; Debugging
                                          (ddmin subset 2 t)))))

                ;; check if the complement of a subset fails
                (let ((complement (test-complements breaks list)))
                  (and complement (progn (format t "Complement with ~a chunks: ~{~a~^, ~}~%"
                                                 (max (1- parts) 2) (map 'list #'car complement)) ; Debugging
                                         (ddmin complement (max (1- parts) 2) nil))))

                ;; check if increasing granularity makes sense
                (and (< parts (length list)) (ddmin list (min (length list) (* 2 parts)) t))

                ;; done: found a 1-minimal subset
                list))))
    (ddmin input 2 t)))

(defun delta-file (filename)
  (annotated-strings->file (delta (file->annotated-strings filename)))
  (format t "unique: ~a, duplicate: ~a~%" *unique-calls* *duplicate-calls*))
