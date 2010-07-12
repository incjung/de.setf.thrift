;;; -*- Mode: lisp; Syntax: ansi-common-lisp; Base: 10; Package: org.apache.thrift.implementation; -*-

(in-package :org.apache.thrift.implementation)

;;; This file defines the abstract '`protocol` layer for the `org.apache.thrift` library.
;;;
;;; copyright 2010 [james anderson](james.anderson@setf.de)
;;;
;;; Licensed to the Apache Software Foundation (ASF) under one
;;; or more contributor license agreements. See the NOTICE file
;;; distributed with this work for additional information
;;; regarding copyright ownership. The ASF licenses this file
;;; to you under the Apache License, Version 2.0 (the
;;; "License"); you may not use this file except in compliance
;;; with the License. You may obtain a copy of the License at
;;; 
;;;   http://www.apache.org/licenses/LICENSE-2.0
;;; 
;;; Unless required by applicable law or agreed to in writing,
;;; software distributed under the License is distributed on an
;;; "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
;;; KIND, either express or implied. See the License for the
;;; specific language governing permissions and limitations
;;; under the License.


;;; The protocol class is the abstract root for comminucation protocol implementations.
;;; It is specialized for each message structure
;;;
;;; protocol
;;; - encoded-protocol
;;;   - binary-protocol (see binary-protocol.lisp)
;;;
;;; The abstract class determines the abstract representation of message components in terms of
;;; and arrangement of Thrift data types. Each concrete protocol class implements the codec for
;;; base data types in terms of signed bytes and unsigned byte sequences. It then delegates to
;;; its input/output transports to decode and encode that data in terms of the transport's
;;; representation.

;;; The stream interface operators are implemented in two forms. A generic interface is specialized
;;; by protocol and/or actual data argument type. In addition a compileer-macro complement performs
;;; compile-time in-line codec expansion when the data type is statically specified. As Thrift
;;; requires all types to be declared statically, IDL files should compile to in-line codecs.
;;;
;;; Type comparisons - both at compile-time and as run-time validation, are according to nominal equality.
;;; As the Thrift type system permits no sub-typing, primtive types are a finite set and the struct/exception
;;; classes permit no super-types.
;;; The only variation would be to to permit integer subtypes for integer container elements, eg i08 sent
;;; where i32 was declared, but that would matter only if supporting a compact protocol.

;;;
;;; interface

(defgeneric stream-read-type (protocol))
(defgeneric stream-read-message-type (protocol))
(defgeneric stream-read-bool (protocol))
(defgeneric stream-read-i08 (protocol))
(defgeneric stream-read-i16 (protocol))
(defgeneric stream-read-i32 (protocol))
(defgeneric stream-read-i64 (protocol))
(defgeneric stream-read-double (protocol))
(defgeneric stream-read-string (protocol))
(defgeneric stream-read-binary (protocol))

(defgeneric stream-read-message-begin (protocol))
(defgeneric stream-read-message (protocol))
(defgeneric stream-read-message-end (protocol))
(defgeneric stream-read-struct-begin (protocol))
(defgeneric stream-read-struct (protocol &optional type))
(defgeneric stream-read-struct-end (protocol))
(defgeneric stream-read-field-begin (protocol))
(defgeneric stream-read-field (protocol &optional type))
(defgeneric stream-read-field-end (protocol))
(defgeneric stream-read-map-begin (protocol))
(defgeneric stream-read-map (protocol &optional key-type value-type))
(defgeneric stream-read-map-end (protocol))
(defgeneric stream-read-list-begin (protocol))
(defgeneric stream-read-list (protocol &optional type))
(defgeneric stream-read-list-end (protocol))
(defgeneric stream-read-set-begin (protocol))
(defgeneric stream-read-set (protocol &optional type))
(defgeneric stream-read-set-end (protocol))

(defgeneric stream-write-type (protocol type-name))
(defgeneric stream-write-message-type (protocol type-name))
(defgeneric stream-write-bool (protocol value))
(defgeneric stream-write-i08 (protocol value))
(defgeneric stream-write-i16 (protocol value))
(defgeneric stream-write-i32 (protocol value))
(defgeneric stream-write-i64 (protocol value))
(defgeneric stream-write-double (protocol value))
(defgeneric stream-write-string (protocol value))
(defgeneric stream-write-binary (protocol value))

(defgeneric stream-write-message-begin (protocol name type seq))
(defgeneric stream-write-message (protocol struct type &key name sequence-number))
(defgeneric stream-write-message-end (protocol))
(defgeneric stream-write-struct-begin (protocol name))
(defgeneric stream-write-struct (protocol value &key name))
(defgeneric stream-write-struct-end (protocol))
(defgeneric stream-write-field-begin (protocol name type id))
(defgeneric stream-write-field (protocol value &key id name type))
(defgeneric stream-write-field-end (protocol))
(defgeneric stream-write-field-stop (protocol))
(defgeneric stream-write-map-begin (protocol key-type value-type size))
(defgeneric stream-write-map (protocol value &optional key-type value-type))
(defgeneric stream-write-map-end (protocol))
(defgeneric stream-write-list-begin (protocol etype size))
(defgeneric stream-write-list (protocol value &optional type))
(defgeneric stream-write-list-end (protocol))
(defgeneric stream-write-set-begin (protocol etype size))
(defgeneric stream-write-set (protocol value &optional type))
(defgeneric stream-write-set-end (protocol))



;;;
;;; macros

(defmacro expand-iff-constant-types (type-variables form &body body)
  "Used in the codec compiler macros to conditionalize expansion on constant types."
  `(cond ((and ,@(loop for tv in type-variables collect `(typep ,tv '(cons (eql quote)))))
          ,@(loop for tv in type-variables collect `(setf ,tv (second , tv)))
          ,@body)
         (t
          ,form)))

#+digitool (setf (ccl:assq 'expand-iff-constant-types ccl:*fred-special-indent-alist*) 2)



;;;
;;; classes

(defclass protocol (stream)
  ((input-transport
    :initform (error "transport is required.") :initarg :input-transport :initarg :transport
    :reader protocol-input-transport)
   (output-transport
    :initform (error "transport is required.") :initarg :output-transport :initarg :transport
    :reader protocol-output-transport)
   (direction
    :initform (error "direction is required.") :initarg :direction
    :reader stream-direction)
   (version-id :initarg :version-id :reader protocol-version-id)
   (version-number :initarg :version-number :reader protocol-version-number)
   (sequence-number :initform 0 :accessor protocol-sequence-number)
   (field-key :initarg :field-key :reader protocol-field-key
              :type (member :number :name))))


(defclass encoded-protocol (protocol)
  ((string-encoder :initarg :string-encoder :reader transport-string-encoder)
   (string-decoder :initarg :string-decoder :reader transport-string-decoder))
  (:default-initargs :charset :utf8))



;;;
;;; protocol operators


(defmethod initialize-instance ((transport encoded-protocol) &rest initargs &key (charset nil))
  (declare (dynamic-extent initargs))
  (multiple-value-bind (decoder encoder)
                       (ecase charset
                         ((nil) (values #'(lambda (string) (map 'vector #'char-code string))
                                        #'(lambda (bytes) (map 'string #'code-char bytes))))
                         (:utf8 (values #'trivial-utf-8:utf-8-bytes-to-string
                                        #'trivial-utf-8:string-to-utf-8-bytes)))
    (apply #'call-next-method transport
           :string-encoder encoder
           :string-decoder decoder
           initargs)))

#-mcl  ;; mcl defines a plain function in terms of stream-direction
(defmethod open-stream-p ((protocol protocol))
  (with-slots (input-transport output-transport) protocol
    (or (open-stream-p input-transport)
        (open-stream-p output-transport))))

(defun protocol-close (protocol &key abort)
  "The protocol close implementation is used by whichever interface the runtime presents for extensions.
 as per the gray interface, close is replaced with a generic function. in other cases, stream-close
 is a generic operator."
  (with-slots (input-transport output-transport stream-direction) protocol
    (when (open-stream-p protocol)
      (close input-transport :abort abort)
      (close output-transport :abort abort)
      (setf (slot-value protocol 'direction) :closed))))

(when (fboundp 'stream-close)
  (defmethod stream-close ((protocol protocol))
    (when (next-method-p) (call-next-method))
    (protocol-close protocol)))

(when (typep #'close 'generic-function)
  (defmethod close ((stream protocol) &rest args)
    (when (next-method-p) (call-next-method))
    (apply #'protocol-close stream args)))


(defgeneric protocol-version (protocol)
  (:method ((protocol protocol))
    (cons (protocol-version-id protocol) (protocol-version-number protocol))))


(defgeneric protocol-find-thrift-class (protocol name)
  (:method ((protocol protocol) (name string))
    (or (find-thrift-class name nil)
        (class-not-found protocol name))))


(defgeneric protocol-next-sequence-number (protocol)
  (:method ((protocol protocol))
    (let ((seq (protocol-sequence-number protocol)))
      (setf (protocol-sequence-number protocol) (1+ seq))
      seq)))


(defmethod stream-position ((protocol protocol) &optional new-position)
  (if new-position
    (stream-position (protocol-input-transport protocol) new-position)
    (stream-position (protocol-input-transport protocol))))


;;;
;;; type  code <-> name operators are specific to each protocol

(defgeneric type-code-name (protocol code)
  )


(defgeneric type-name-code (protocol name)
  )


(defgeneric message-type-code (protocol message-name)
  )

(defgeneric message-type-name (protocol type-code)
  )



;;;
;;; input implementation

(defmethod stream-read-message-begin ((protocol protocol))
  "Read a message header strictly. A backwards compatible implementation would read the entire I32, in order
 to use a value w/o the #x80000000 tag bit as a string length, but that is not necessary when reading strictly.
 The jira [issue](https://issues.apache.org/jira/browse/THRIFT-254) indicates that all implementions write
 strict by default, and that a 'next' release should treat non-strict messages as bugs.

 This version recognizes the layout established by the compact protocol, whereby the first byte is the
 protocol id and subsequent to that is specific to the protocol."

  (let* ((id (logand (stream-read-i08 protocol) #xff))          ; actually unsigned
         (ver (logand (stream-read-i08 protocol) #xff))         ; actually unsigned
         (type-name (stream-read-message-type protocol)))
    (unless (and (= (protocol-version-id protocol) id) (= (protocol-version-number protocol) ver))
      (invalid-protocol-version protocol id ver))
    (let ((name (stream-read-string protocol))
          (sequence (stream-read-i32 protocol)))
      (values name type-name sequence))))


(defmethod stream-read-message ((protocol protocol))
  "Perform a generic 'read' of a complete message. This is here for testing only, as messages are not
 first-class. They protocol interprets them on-the-fly as either requests, in which case the arguments
 are spread and passed to the requested operation on the fly, or responses in which case either the
 id=0 result value is returned, or som other field is present instead and designates an exception to
 signal. see stream-send-request and stream-receive-response."
  (multiple-value-bind (name type sequence)
                       (stream-read-message-begin protocol)
    (let ((body (stream-read-struct protocol name)))
      (stream-read-message-end protocol)
      (values name type sequence body))))

(defmethod stream-read-message-end ((protocol protocol)))



(defmethod stream-read-struct-begin ((protocol protocol))
  (let ((name (stream-read-string protocol)))
    (protocol-find-thrift-class protocol name)))

(defmethod stream-read-struct-end ((protocol protocol)))

(defmethod stream-read-struct ((protocol protocol) &optional expected-type)
  "Interpret an encoded structure as either an expcetion or a struct depending on the specified class.
 Decode each field in turn. When decoding exceptions, build the initargs list and construct it as the
 last step. Otherwise allocate an instacen and bind each value in succession.
 Should the field fail to correspond to a known slot, delegate unknown-field to the class for a field
 defintion. If it supplies none, then resort to the class."
  
  ;; Were it slot classes only, a better protocol would be (setf slot-value-using-class), but that does not
  ;; apply to exceptions. Given both cases, this is coded to stay symmetric.
  (let* ((class (stream-read-struct-begin protocol))
         (type (class-name class)))
    (unless (or (null expected-type) (equal type expected-type))
      (invalid-struct-type protocol expected-type type))
    (if (subtypep type 'condition)
      ;; allocation-instance and setf slot-value) are not standard for conditions
      ;; if class-slots (as required by class-field-definitions) is not defined, this will need changes
      (let ((initargs ())
            (fields (class-field-definitions class))
            (fd nil))
        (loop (multiple-value-bind (value name id field-type)
                                   (stream-read-field protocol)
                (cond ((eq field-type 'stop)
                       (stream-read-struct-end protocol)
                       (return (apply #'make-condition type initargs)))
                      ((setf fd (or (find id fields :key #'field-definition-identifier-number :test #'eql)
                                    (unknown-field class name id field-type value)))
                       (setf (getf initargs (field-definition-initarg fd)) value))
                      (t
                       (unknown-field protocol name id field-type value))))))
      (let* ((instance (allocate-instance class))
             (fields (class-field-definitions class))
             (fd nil))
        (loop (multiple-value-bind (value name id field-type)
                                   (stream-read-field protocol)
                (cond ((eq field-type 'stop)
                       (stream-read-struct-end protocol)
                       (return instance))
                      ((setf fd (or (find id fields :key #'field-definition-identifier-number :test #'eql)
                                    (unknown-field class name id field-type value)))
                       (setf (slot-value instance (field-definition-name fd))
                             value))
                      (t
                       (unknown-field protocol name id field-type value)))))))))

(define-compiler-macro stream-read-struct (&whole form prot &optional type &environment env)
  (expand-iff-constant-types (type) form
    (with-optional-gensyms (prot) env
      (with-gensyms (extra-initargs)
        (let* ((class (find-thrift-class type))
              (field-definitions (class-field-definitions class)))
          `(let* ((class (stream-read-struct-begin protocol))
                  (type (class-name class)))
             (unless (equal type ',type)
               (invalid-struct-type protocol ',type type))
             (let (,@(loop for fd in field-definitions
                           collect (list (field-definition-name fd) nil))
                   (,extra-initargs nil))
               ,(generate-struct-decoder prot field-definitions extra-initargs))
             (apply #'make-struct class
                    ,@(loop for fd in field-definitions
                            collect (list (field-definition-initarg fd) (field-definition-name fd)))
                    ,extra-initargs)))))))



(defmethod stream-read-field-begin ((protocol protocol))
  (let ((type nil)
        (id 0)
        (name nil))
    (ecase (protocol-field-key protocol)
      (:identifier (setf type (stream-read-type protocol))
                   (unless (eq type 'stop)
                     (setf id (stream-read-i16 protocol))))
      (:name (setf name (stream-read-string protocol)
                   ;; NB the bnf is broke here, as it says "T_STOP | <field_name> <field_type> <field_id>"
                   ;; but there's no way to distinguish the count field of a string from the stop code
                   ;; so perhaps this is excluded for a binary protocol and works only if the
                   ;; protocol's field are themselves self-describing
                   type (stream-read-type protocol))))
    (values name id type)))

(defmethod stream-read-field-end ((protocol protocol)))

(defmethod stream-read-field((protocol protocol) &optional type)
  (multiple-value-bind (name id read-type)
                       (stream-read-field-begin protocol)
    (if (eq read-type 'stop)
      (values nil nil 0 'stop)
      (let* ((value (stream-read-value-as protocol read-type)))
        (stream-read-field-end protocol)
        (when type (unless (equal type read-type)
                     (invalid-field-type protocol nil id name type value)))
        (values value name id)))))

;;; a compiler macro would find no use, since the macro expansion for reading a struct already
;;; incorporates dispatches on field id to call read-value-as, and stream-read-field itself
;;; never knows the type at compile time.



(defmethod stream-read-map-begin ((protocol protocol))
  ; t_key t_val size
  (values (stream-read-type protocol)
          (stream-read-type protocol)
          (stream-read-i32 protocol)))

(defmethod stream-read-map-end ((protocol protocol)))

(defmethod stream-read-map((protocol protocol) &optional key-type value-type)
  (let ((map (thrift:map)))
    (multiple-value-bind (read-key-type read-value-type size) (stream-read-map-begin protocol)
      (unless (or (null key-type) (equal read-key-type key-type))
        (invalid-element-type protocol 'thrift:map key-type read-key-type))
      (unless (or (null value-type) (equal read-value-type value-type))
        (invalid-element-type protocol 'thrift:map value-type read-value-type))
      (unless (typep size 'field-size)
        (invalid-field-size protocol 0 "" 'field-size size))
      (dotimes (i size)
        ;; no type check - presume the respective reader is correct.
        (setf (gethash (stream-read-value-as protocol key-type) map)
              (stream-read-value-as protocol value-type)))
      (stream-read-map-end protocol)
      map)))

(define-compiler-macro stream-read-map (&whole form prot &optional key-type value-type &environment env)
  (expand-iff-constant-types (key-type value-type) form
    (with-optional-gensyms (prot) env
      `(multiple-value-bind (key-type value-type size) (stream-read-map-begin ,prot)
         (unless (equal key-type ',key-type)
           (invalid-element-type ,prot 'thrift:map ',key-type key-type))
         (unless (equal value-type ',value-type)
           (invalid-element-type protocol 'thrift:map ',value-type value-type))
         (unless (typep size 'field-size)
           (invalid-field-size ,prot 0 "" 'field-size size))
         (dotimes (i size)
           ;; no type check - presume the respective reader is correct.
           (setf (gethash (stream-read-value-as protocol ',key-type) map)
                 (stream-read-value-as protocol ',value-type)))
         (stream-read-map-end ,prot)
         map))))



(defmethod stream-read-list-begin ((protocol protocol))
  ; t_elt size
  (values (stream-read-type protocol)
          (stream-read-i32 protocol)))

(defmethod stream-read-list-end ((protocol protocol)))

(defmethod stream-read-list((protocol protocol) &optional type)
  (multiple-value-bind (read-type size)
                       (stream-read-list-begin protocol)
    (when type
      (unless (equal read-type type)
        (invalid-element-type protocol 'thrift:list type read-type)))
    (unless (typep size 'field-size)
        (invalid-field-size protocol 0 "" 'field-size size))
    (prog1 (loop for i from 0 below size
                 collect (stream-read-value-as protocol read-type))
      (stream-read-list-end protocol))))

(define-compiler-macro stream-read-list (&whole form prot &optional type &environment env)
  (expand-iff-constant-types (type) form
    (with-optional-gensyms (prot) env
    `(multiple-value-bind (type size)
                          (stream-read-list-begin ,prot)
       (unless (equal type ',type)
         (invalid-element-type ,prot 'thrift:list ',type type))
       (unless (typep size 'field-size)
         (invalid-field-size ,prot 0 "" 'field-size size))
       (prog1 (loop for i from 0 below size
                    collect (stream-read-value-as ,prot ',type))
         (stream-read-list-end ,prot))))))



(defmethod stream-read-set-begin ((protocol protocol))
  (values (stream-read-type protocol)
          (stream-read-i32 protocol)))

(defmethod stream-read-set-end ((protocol protocol)))

(defmethod stream-read-set((protocol protocol) &optional type)
  (multiple-value-bind (read-type size)
                       (stream-read-set-begin protocol)
    (when type
      (unless (equal read-type type)
        (invalid-element-type protocol 'thrift:set type read-type)))
    (unless (typep size 'field-size)
      (invalid-field-size protocol 0 "" 'field-size size))
    (prog1 (loop for i from 0 below size
                 collect (stream-read-value-as protocol read-type))
      (stream-read-set-end protocol))))

(define-compiler-macro stream-read-set (&whole form prot &optional type &environment env)
  (expand-iff-constant-types (type) form
    (with-optional-gensyms (prot) env
    `(multiple-value-bind (type size)
                          (stream-read-set-begin ,prot)
       (unless (equal type ',type)
         (invalid-element-type ,prot 'thrift:set ',type type))
       (unless (typep size 'field-size)
         (invalid-field-size ,prot 0 "" 'field-size size))
       (prog1 (loop for i from 0 below size
                    collect (stream-read-value-as ,prot ',type))
         (stream-read-set-end ,prot))))))



(defmethod stream-read-enum ((protocol protocol) type)
  "Read an i32 and verify type"
  (let ((value (stream-read-i32 protocol)))
    (unless (typep value type)
      (invalid-enum protocol type value))
    value))

(define-compiler-macro stream-read-enum (&whole form prot type)
  (expand-iff-constant-types (type) form
    #+thrift-check-types
    `(let ((value (stream-read-i32 ,prot)))
       (unless (typep value ',type)
         (invalid-enum protocol ',type value))
       value)
    `(stream-read-i32 ,prot)))


(defgeneric stream-read-value-as (protocol type)
  (:documentation "Read a value if a specified type.")
  (:method ((protocol protocol) (type-code fixnum))
    (stream-read-value-as protocol (type-code-name protocol type-code)))

  (:method ((protocol protocol) (type-code (eql 'bool)))
    (stream-read-bool protocol))
  (:method ((protocol protocol) (type-code (eql 'byte)))
    ;; call through the i08 methods as byte ops are transport, not protocol methods
    (stream-read-i08 protocol))
  (:method ((protocol protocol) (type-code (eql 'i08)))
    (stream-read-i08 protocol))
  (:method ((protocol protocol) (type-code (eql 'i16)))
    (stream-read-i16 protocol))
  (:method ((protocol protocol) (type-code (eql 'enum)))
    ;; as a fall-back
    (stream-read-i16 protocol))
  (:method ((protocol protocol) (type-code (eql 'i32)))
    (stream-read-i32 protocol))
  (:method ((protocol protocol) (type-code (eql 'i64)))
    (stream-read-i64 protocol))

  (:method ((protocol protocol) (type-code (eql 'double)))
    (stream-read-double protocol))

  (:method ((protocol protocol) (type-code (eql 'string)))
    (stream-read-string protocol))
  (:method ((protocol protocol) (type-code (eql 'binary)))
    (stream-read-binary protocol))

  (:method ((protocol protocol) (type-code (eql 'struct)))
    (stream-read-struct protocol))
  (:method ((protocol protocol) (type-code (eql 'thrift:map)))
    (stream-read-map protocol))
  (:method ((protocol protocol) (type-code (eql 'thrift:list)))
    (stream-read-list protocol))
  (:method ((protocol protocol) (type-code (eql 'thrift:set)))
    (stream-read-set protocol)))


(define-compiler-macro stream-read-value-as (&whole form protocol type)
  "Given a constant type, generate the respective read operations.
 Recognizes all thrift types, container x element type combinations
 and struct classes. A void specification yields no values.
 If the type is not constant, declare to expand, which leaves the dispatch
 to run-time interpretation."

  (typecase type
    ;; just in case
    (fixnum (setf type (type-name-class type)))
    ((cons (eql quote)) (setf type (second type)))
    ;; if it's not constante, decline to expand
    (t (return-from stream-read-value-as form)))

  ;; given a constant type, attempt an expansion
  (etypecase type
    ((eql void)
     (values))
    (base-type
     `(,(cons-symbol :org.apache.thrift.implementation
                     :stream-read- type) ,protocol))
    ((member thrift:set thrift:list thrift:map)
     (warn "Compiling generic container decoder: ~s." type)
     `(,(cons-symbol :org.apache.thrift.implementation
                     :stream-read- type) ,protocol))
    (container-type
     (destructuring-bind (type element-type) type
       `(,(cons-symbol :org.apache.thrift.implementation
                       :stream-read- type) ,protocol ',element-type)))
    (struct-type
     `(stream-read-struct ,protocol ',(second type)))
    (enum-type
     `(stream-read-enum ,protocol ',(second type)))))                       
  



;;; output implementation 


(defmethod stream-write-message-begin ((protocol protocol) name type sequence)
  (stream-write-i08 protocol (protocol-version-id protocol))
  (stream-write-i08 protocol (protocol-version-number protocol))
  (stream-write-message-type protocol type)
  (stream-write-string protocol name)
  (stream-write-i32 protocol sequence))

(defmethod stream-write-message ((protocol protocol) (object standard-object) (type (eql 'call))
                                 &key (name (class-identifier object))
                                 (sequence-number (protocol-next-sequence-number protocol)))
  (stream-write-message-begin protocol name type sequence-number)
  (stream-write-struct protocol object :name name)
  (stream-write-message-end protocol))

(defmethod stream-write-message ((protocol protocol) (object standard-object) (type (eql 'oneway))
                                 &key (name (class-identifier object))
                                 (sequence-number (protocol-next-sequence-number protocol)))
  (stream-write-message-begin protocol name type sequence-number)
  (stream-write-struct protocol object :name name)
  (stream-write-message-end protocol))

(defmethod stream-write-message ((protocol protocol) (object standard-object) (type t)
                                 &key (name (class-identifier object))
                                 (sequence-number (protocol-sequence-number protocol)))
  (stream-write-message-begin protocol name type sequence-number)
  (stream-write-struct protocol object :name name)
  (stream-write-message-end protocol))
  

(defmethod stream-write-message-end ((protocol protocol))
  (stream-force-output (protocol-output-transport protocol)))


(defgeneric stream-write-exception (protocol exception)
  (:method ((protocol protocol) (exception thrift-error))
    (stream-write-message protocol exception 'exception
                          :name (class-identifier exception)))
  
  (:method ((protocol protocol) (exception condition))
    (stream-write-message protocol
                          (make-instance 'application-error :condition exception)
                          'exception)))



(defmethod stream-write-struct-begin ((protocol protocol) (name string))
  (stream-write-string protocol name))

(defmethod stream-write-struct-end ((protocol protocol)))

(defmethod stream-write-struct ((protocol protocol) (value thrift-object) &key (name (class-identifier value)))
  (stream-write-struct-begin protocol name)
  (dolist (sd (class-field-definitions value))
    (let ((name (field-definition-name sd)))
      ;; requirement constraints should be embodied in the slot initform
      ;; a slot which does not require initialization is skipped if not bound
      (when (slot-boundp value name)
        (stream-write-field protocol (slot-value value name)
                            :id (field-definition-identifier-number sd)
                            :name (field-definition-identifier sd)
                            :type (field-definition-type sd)))))
  (stream-write-field-stop protocol)
  (stream-write-struct-end protocol))

(defmethod stream-write-struct ((protocol protocol) (value list) &key (name (error "The class is required.")))
  (let* ((class (find-thrift-class name))
        (fields (class-field-definitions class))
        (identifier (class-identifier class)))
    (stream-write-struct-begin protocol identifier)
    (loop for (id . field-value) in value
          do (let ((fd (or (find id fields :key #'field-definition-identifier-number)
                           (error 'unknown-field protocol :id id))))
               (stream-write-field protocol field-value
                                   :id id
                                   :name (field-definition-identifier fd)
                                   :type (field-definition-type fd))))
    (stream-write-field-stop protocol)
    (stream-write-struct-end protocol)))

(define-compiler-macro stream-write-struct (&whole form prot value &key name &environment env)
  (expand-iff-constant-types (name) form
    (let ((field-definitions (class-field-definitions name)))
      (if (typep value '(cons (eql list)))
        ;; if it's a literal environment, expand it in-line
        (with-optional-gensyms (prot) env
          `(progn (stream-write-struct-begin ,prot ,name)
                  ,@(loop for (nil id variable) in (rest value)
                          for fd = (or (find id field-definitions :key #'field-definition-identifier-number)
                                       (error "Field id not found: ~s, ~s" id name))
                          collect `(stream-write-field ,prot ,variable
                                                       :name ,(field-definition-identifier fd)
                                                       :type ',(field-definition-type fd)
                                                       :id ,id))
                  (stream-write-field-stop ,prot)
                  (stream-write-struct-end ,prot)))
        ;; otherwise expand with instance field refences
        (with-optional-gensyms (prot value) env
          `(progn (stream-write-struct-begin ,prot ,name)
                  ,@(loop for fd in field-definitions
                          collect `(stream-write-field ,prot (,(field-definition-reader fd) ,value)
                                                       :name ,(field-definition-identifier fd)
                                                       :type ',(field-definition-type fd)
                                                       :id ,(field-definition-identifier-number fd)))
                  (stream-write-field-stop ,prot)
                  (stream-write-struct-end ,prot)))))))



(defmethod stream-write-field-begin ((protocol protocol) (name string) type id)
  (ecase (protocol-field-key protocol)
    (:identifier (stream-write-type protocol type)
                 (stream-write-i16 protocol id))
    (:name (stream-write-string protocol name)
           (stream-write-type protocol type))))

(defmethod stream-write-field-end ((protocol protocol)))

(defmethod stream-write-field-stop ((protocol protocol))
  (stream-write-type protocol 'stop))

(defmethod stream-write-field ((protocol protocol) (value t) &key name id (identifier id) (type (thrift:type-of value)))
  (stream-write-field-begin protocol name type identifier)
  (stream-write-value-as protocol value type)
  (stream-write-field-end protocol))

(define-compiler-macro stream-write-field (&whole form prot value &key name id type &environment env)
  (expand-iff-constant-types (type) form
    (with-optional-gensyms (prot) env
    `(progn (stream-write-field-begin ,prot ,name ',type ,id)
            (stream-write-value-as ,prot ,value ',type)
            (stream-write-field-end ,prot)))))



(defmethod stream-write-map-begin ((protocol protocol) key-type value-type size)
  (stream-write-type protocol key-type)
  (stream-write-type protocol value-type)
  (stream-write-i32 protocol size))

(defmethod stream-write-map-end ((protocol protocol)))

(defmethod stream-write-map ((protocol protocol) value &optional key-type value-type)
  (let ((size (hash-table-count value)))
    ;; nb. no need to check size as the hash table size is constrained by array size limits.
    (unless (and key-type value-type)
      (multiple-value-bind (k-type v-type)
                           (loop for value being each hash-value of value
                                 using (hash-key key)
                                 do (return (values (thrift:type-of key) (thrift:type-of value))))
        (unless key-type (setf key-type k-type))
        (unless value-type (setf value-type v-type)))
      (stream-write-map-begin protocol key-type value-type size)
      (loop for element-value being each hash-value of value
            using (hash-key element-key)
            do (progn (stream-write-value-as protocol element-key key-type)
                      (stream-write-value-as protocol element-value value-type)))
      (stream-write-map-end protocol))))

(define-compiler-macro stream-write-map (&whole form prot value &optional key-type value-type &environment env)
  (expand-iff-constant-types (key-type value-type) form
    (with-optional-gensyms (prot value) env
      `(let ((size (hash-table-count ,value)))
         ;; nb. no need to check size as the hash table size is constrained by array size limits.
         (stream-write-map-begin ,prot ',key-type ',value-type size)
         (loop for element-value being each hash-value of value
               using (hash-key element-key)
               do (progn #+thrift-check-types (assert (typep element-value ',value-type))
                         #+thrift-check-types (assert (typep element-key ',key-type))
                         (stream-write-value-as protocol element-key ',key-type)
                         (stream-write-value-as protocol element-value ',value-type)))
         (stream-write-map-end ,prot)))))



(defmethod stream-write-list-begin ((protocol protocol) (type t) length)
  (stream-write-type protocol type)
  (stream-write-i32 protocol length))

(defmethod stream-write-list-end ((protocol protocol)))

(defmethod stream-write-list ((protocol protocol) (value list) &optional
                              (type (if value (thrift:type-of (first value)) (error "The element type is required."))))
  (let ((size (list-length value)))
    (unless (typep size 'field-size)
      (invalid-field-size protocol 0 "" 'field-size size))
    (stream-write-list-begin protocol type size)
    (dolist (elt value)
      (stream-write-value-as protocol elt type))
    (stream-write-list-end protocol)))

(define-compiler-macro stream-write-list (&whole form prot value &optional type &environment env)
  (expand-iff-constant-types (type) form
    (with-optional-gensyms (prot value) env
      `(let ((size (list-length ,value)))
         (unless (typep size 'field-size)
           (invalid-field-size ,prot 0 "" 'field-size size))
         (stream-write-list-begin ,prot ',type size)
         (dolist (element ,value)
           #+thrift-check-types (assert (typep element ',type))
           (stream-write-value-as ,prot element ',type))
         (stream-write-list-end ,prot)))))



(defmethod stream-write-set-begin ((protocol protocol) (type t) length)
  (stream-write-type protocol type)
  (stream-write-i32 protocol length))

(defmethod stream-write-set-end ((protocol protocol)))

(defmethod stream-write-set ((protocol protocol) (value list) &optional
                             (type (if value (thrift:type-of (first value)) (error "The element type is required."))))
  (let ((size (list-length value)))
    (unless (typep size 'field-size)
      (invalid-field-size protocol 0 "" 'field-size size))
    (stream-write-set-begin protocol type size)
    (dolist (element value)
      #+thrift-check-types (assert (typep element type))
      (stream-write-value-as protocol element type))
    (stream-write-set-end protocol)))

(define-compiler-macro stream-write-set (&whole form prot value &optional type &environment env)
  (expand-iff-constant-types (type) form
    (with-optional-gensyms (prot value) env
    `(let ((size (list-length ,value)))
       (unless (typep size 'field-size)
         (invalid-field-size ,prot 0 "" 'field-size size))
       (stream-write-set-begin ,prot ',type size)
       (dolist (element ,value)
         #+thrift-check-types (assert (typep element ',type))
         (stream-write-value-as ,prot element ',type))
       (stream-write-set-end ,prot)))))



(defgeneric stream-write-value (protocol value)
  (:method ((protocol protocol) (value null))
    (stream-write-bool protocol value))
  (:method ((protocol protocol) (value (eql t)))
    (stream-write-bool protocol value))
  (:method ((protocol protocol) (value integer))
    (etypecase value
     (i08 (stream-write-i08 protocol value))
     (i16 (stream-write-i16 protocol value))
     (i32 (stream-write-i32 protocol value))
     (i64 (stream-write-i64 protocol value))))

  (:method ((protocol protocol) (value float))
    (unless (typep value 'double)
      (setf value (float value 1.0d0)))
    (stream-write-double protocol value))

  (:method ((protocol protocol) (value string))
    (stream-write-string protocol value))
  (:method ((protocol protocol) (value vector))
    (stream-write-binary protocol value))
  
  (:method ((protocol protocol) (value thrift-object))
    (stream-write-struct protocol value))
  (:method ((protocol protocol) (value hash-table))
    (stream-write-map protocol value))
  (:method ((protocol protocol) (value list))
    (stream-write-list protocol value)))


(defgeneric stream-write-value-as (protocol value type)
  (:method ((protocol protocol) (value t) (type-code fixnum))
    (stream-write-value-as protocol value (type-code-name protocol type-code)))

  (:method ((protocol protocol) (value t) (type (eql 'bool)))
    (stream-write-bool protocol value))
  (:method ((protocol protocol) (value integer) (type (eql 'byte)))
    (stream-write-i08 protocol value))
  (:method ((protocol protocol) (value integer) (type (eql 'i08)))
    (stream-write-i08 protocol value))
  (:method ((protocol protocol) (value integer) (type (eql 'i16)))
    (stream-write-i16 protocol value))
  (:method ((protocol protocol) (value integer) (type (eql 'enum)))
    ;; as a fall-back
    (stream-write-i16 protocol value))
  (:method ((protocol protocol) (value integer) (type (eql 'i32)))
    (stream-write-i32 protocol value))
  (:method ((protocol protocol) (value integer) (type (eql 'i64)))
    (stream-write-i64 protocol value))

  (:method ((protocol protocol) (value float) (type (eql 'double)))
    (unless (typep value 'double)
      (setf value (float value 1.0d0)))
    (stream-write-double protocol value))

  (:method ((protocol protocol) (value string) (type (eql 'string)))
    (stream-write-string protocol value))
  (:method ((protocol protocol) (value vector) (type (eql 'binary)))
    (stream-write-binary protocol value))

  (:method ((protocol protocol) (value hash-table) (type (eql 'struct)))
    (stream-write-struct protocol value))
  (:method ((protocol protocol) (value hash-table) (type (eql 'thrift:map)))
    (stream-write-map protocol value))
  (:method ((protocol protocol) (value list) (type (eql 'thrift:list)))
    (stream-write-list protocol value))
  (:method ((protocol protocol) (value list) (type (eql 'thrift:set)))
    (stream-write-set protocol value)))


(define-compiler-macro stream-write-value-as (&whole form protocol value type)
  "See stream-read-value-as."

  (typecase type
    ;; just in case
    (fixnum (setf type (type-name-class type)))
    ((cons (eql quote)) (setf type (second type)))
    ;; if it's not constant, decline to expand
    (t (return-from stream-write-value-as form)))

  ;; given a constant type, attempt an expansion
  (etypecase type
    ((eql void)
     nil)
    (base-type
     `(,(cons-symbol :org.apache.thrift.implementation
                     :stream-write- type) ,protocol ,value))
    ((member thrift:set thrift:list thrift:map)
     (warn "Compiling generic container encoder: ~s." type)
     `(,(cons-symbol :org.apache.thrift.implementation
                     :stream-write- type) ,protocol ,value))
    (container-type
     (destructuring-bind (type element-type) type
       `(,(cons-symbol :org.apache.thrift.implementation
                       :stream-write- type) ,protocol ,value ',element-type)))
    (struct-type
     `(stream-read-struct ,protocol ,value ',(second type)))
    (enum-type
     `(stream-read-enum ,protocol ,value ',(second type)))))


;;;
;;; protocol exception operators

(defgeneric application-error (protocol &key condition)
  (:method ((protocol protocol) &key condition)
    (error 'application-error :protocol protocol
           :condition condition)))


(defgeneric class-not-found (protocol name)
  (:method ((protocol protocol) name)
    (or *thrift-prototype-class*
        (error 'class-not-found-error :protocol protocol :name name))))


(defgeneric invalid-enum (protocol type datum)
  (:method ((protocol protocol) type datum)
    (error 'enum-type-error :protocol protocol :expected-type type :datum datum)))


(defgeneric unknown-field (protocol field-name field-id field-type value)
  (:documentation "Called when a decoded field is not present in the specified type.
 The base method for protocols ignores it.
 A prototypical protocol/class combination could extend the class by adding a
 field definition as per the name/id/type specified and bindng the value")

  (:method ((protocol protocol) (name t) (id t) (type t) (value t))
    nil))


(defgeneric invalid-field-size (protocol field-id field-name expected-type size)
  (:documentation "Called when a read structure field exceeds the dimension limit.
 The base method for binary protocols signals a field-size-error")

  (:method ((protocol protocol) (id integer) (name t) (expected-type t) (size t))
    (error 'field-size-error :protocol protocol
           :name name :id id :expected-type expected-type :datum size)))


(defgeneric invalid-field-type (protocol structure-type field-id field-name expected-type value)
  (:documentation "Called when a read structure field is not present in the specified type.
 The base method for binary protocols signals a field-type-error")

  (:method ((protocol protocol) (structure-type t) (id t) (name t) (expected-type t) (value t))
    (error 'field-type-error :protocol protocol
           :structure-type structure-type :name name :id id :expected-type expected-type :datum value)))


(defgeneric invalid-element-type (protocol container-type expected-type type)
  (:documentation "Called when the element type of a received compound value is not the specified type.
 The base method for binary protocols signals an element-type-error")

  (:method ((protocol protocol) container-type (expected-type t) (type t))
    (error 'element-type-error :protocol protocol
           :container-type container-type :expected-type expected-type :element-type type)))


(defgeneric unknown-method (protocol name sequence message)
  (:method ((protocol protocol) name (sequence t) (message t))
    (error 'unknown-method-error :name name :request message)))


(defgeneric protocol-error (protocol type &optional message &rest arguments)
  (:method ((protocol protocol) type &optional message &rest arguments)
    (error 'protocol-error :type type :message message :message-arguments arguments)))


(defgeneric invalid-protocol-version (protocol id version)
  (:method ((protocol protocol) id version)
    (error 'protocol-version-error :protocol protocol :datum (cons id version)
           :expected-type (protocol-version protocol))))


(defgeneric invalid-struct-type (protocol type datum)
  (:method ((protocol protocol) type datum)
    (error 'struct-type-error :protocol protocol :expected-type type :datum datum)))


;;;
;;; response processing exception interface

(defgeneric response-exception (protocol message-name sequence-number exception)
  (:documentation "Called when an exception is read as a response. The base method signals an error.")

  (:method ((protocol protocol) (message-name t) (sequence-number t) (exception condition))
    "The base method signals an error."
    (error exception)))

(defgeneric request-exception (protocol message-name sequence-number exception)
  (:documentation "Called when an exception is read as a request. The base method signals an error.")

  (:method ((protocol protocol) (message-name t) (sequence-number t) (exception condition))
    "The base method signals an error."
    (error exception)))

(defgeneric unexpected-request (protocol message-name sequence-number exception)
  (:documentation "Called when a request is read out of context, eg. by a client. The base method signals an error.")

  (:method ((protocol protocol) (message-name t) (sequence-number t) (content t))
    "The base method signals an error."
    (error "Unexpected request: ~s ~s ~s ~s."
           protocol message-name sequence-number content)))

(defgeneric unexpected-response (protocol message-name sequence-number exception)
  (:documentation "Called when a response is read out of context, eg. by a server The base method signals an error.")

  (:method ((protocol protocol) (message-name t) (sequence-number t) (content t))
    "The base method signals an error."
    (error "Unexpected response: ~s ~s ~s ~s."
           protocol message-name sequence-number content)))