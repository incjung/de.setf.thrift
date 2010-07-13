// Copyright (c) 2008- Patrick Collison <patrick@collison.ie>
// Copyright (c) 2006- Facebook
//
// Distributed under the Thrift Software License
//
// See accompanying file LICENSE or visit the Thrift site at:
// http://developers.facebook.com/thrift/

#include <string>
#include <fstream>
#include <iostream>
#include <vector>

#include <stdlib.h>
#include <boost/tokenizer.hpp>
#include <sys/stat.h>
#include <sys/types.h>
#include <sstream>
#include <string>
#include <algorithm>

#include "platform.h"
#include "t_oop_generator.h"
using namespace std;


/**
 * Common Lisp code generator.
 *
 * @author Patrick Collison <patrick@collison.ie>
 */
class t_cl_generator : public t_oop_generator {
 public:
  t_cl_generator(
      t_program* program,
      const std::map<std::string, std::string>& parsed_options,
      const std::string& option_string)
    : t_oop_generator(program)
  {
    out_dir_base_ = "gen-cl";
  }

  void init_generator();
  void close_generator();

  void generate_typedef     (t_typedef*  ttypedef);
  void generate_enum        (t_enum*     tenum);
  void generate_const       (t_const*    tconst);
  void generate_struct      (t_struct*   tstruct);
  void generate_xception    (t_struct*   txception);
  void generate_service     (t_service*  tservice);
  void generate_cl_struct (std::ofstream& out, t_struct* tstruct, bool is_exception);
  void generate_cl_struct_internal (std::ofstream& out, t_struct* tstruct, bool is_exception);
  void generate_exception_sig(std::ofstream& out, t_function* f);
  std::string render_const_value(t_type* type, t_const_value* value);

  std::string cl_autogen_comment();
  void package_def(std::ofstream &out, std::string name);
  void package_in(std::ofstream &out, std::string name);
  std::string generated_package();
  std::string prefix(std::string name);
  std::string package_of(t_program* program);
  std::string package();

  std::string type_name(t_type* ttype);
  std::string typespec (t_type *t);
  std::string function_signature(t_function* tfunction);
  std::string argument_list(t_struct* tstruct);

  std::string cl_docstring(std::string raw);

 private:

  int temporary_var;
  /**
   * Isolate the variable definitions, as they can require structure definitions
   */
  std::ofstream f_types_;
  std::ofstream f_vars_;

};


void t_cl_generator::init_generator() {
  MKDIR(get_out_dir().c_str());

  temporary_var = 0;

  string f_types_name = get_out_dir()+"/"+program_name_+"-types.lisp";
  string f_vars_name = get_out_dir()+"/"+program_name_+"-vars.lisp";

  f_types_.open(f_types_name.c_str());
  f_types_ << cl_autogen_comment() << endl;
  f_vars_.open(f_vars_name.c_str());
  f_vars_ << cl_autogen_comment() << endl;

  package_def(f_types_, program_name_);
  package_in(f_types_, program_name_);
  package_in(f_vars_, program_name_);
}

string t_cl_generator::package_of(t_program* program) {
  string prefix = program->get_namespace("cl");
  return prefix.empty() ? "thrift-generated" : prefix;
}

string t_cl_generator::package() {
  return package_of(program_);
}

string t_cl_generator::prefix(string symbol) {
  return "\"" + symbol + "\"";
}

string t_cl_generator::cl_autogen_comment() {
  return
    std::string(";;; ") + " -*- Package: " + package() + " -*-\n" +
    ";;;\n" +
    ";;; Autogenerated by Thrift\n" +
    ";;; DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING\n";
}

string t_cl_generator::cl_docstring(string raw) {
  replace(raw.begin(), raw.end(), '"', '\'');
  return raw;
}


void t_cl_generator::close_generator() {
  f_types_.close();
  f_vars_.close();
}

string t_cl_generator::generated_package() {
  return program_->get_namespace("cpp");
}

/***
 * Generate a package definition. Add use references equivalent to the idl file's include statements.
 */
void t_cl_generator::package_def(std::ofstream &out, string name) {
  const vector<t_program*>& includes = program_->get_includes();

  out << "(thrift:def-package :" << package();
  if ( includes.size() > 0 ) {
    out << " :use (";
    for (size_t i = 0; i < includes.size(); ++i) {
      out << " :" << includes[i]->get_name();
    }
    out << ")";
  }
  out << ")" << endl << endl;
}

void t_cl_generator::package_in(std::ofstream &out, string name) {
  out << "(in-package :" << package() << ")" << endl << endl;
}

void t_cl_generator::generate_typedef(t_typedef* ttypedef) {}

void t_cl_generator::generate_enum(t_enum* tenum) {
  f_types_ << "(thrift:def-enum " << prefix(tenum->get_name()) << endl;

  vector<t_enum_value*> constants = tenum->get_constants();
  vector<t_enum_value*>::iterator c_iter;
  int value = -1;

  indent_up();
  f_types_ << indent() << "(";
  for (c_iter = constants.begin(); c_iter != constants.end(); ++c_iter) {
    if ((*c_iter)->has_value()) {
      value = (*c_iter)->get_value();
    } else {
      ++value;
    }

    if(c_iter != constants.begin()) f_types_ << endl << indent() << " ";

    f_types_ << "(\"" << (*c_iter)->get_name() << "\" . " << value << ")";
  }
  indent_down();
  f_types_ << "))" << endl << endl;
}

/**
 * Generate a constant value
 */
void t_cl_generator::generate_const(t_const* tconst) {
  t_type* type = tconst->get_type();
  string name = tconst->get_name();
  t_const_value* value = tconst->get_value();

  f_vars_ << "(thrift:def-constant " << prefix(name) << " " << render_const_value(type, value) << ")"
          << endl << endl;
}

/**
 * Prints the value of a constant with the given type. Note that type checking
 * is NOT performed in this function as it is always run beforehand using the
 * validate_types method in main.cc
 */
string t_cl_generator::render_const_value(t_type* type, t_const_value* value) {
  type = get_true_type(type);
  std::ostringstream out;
  if (type->is_base_type()) {
    t_base_type::t_base tbase = ((t_base_type*)type)->get_base();
    switch (tbase) {
    case t_base_type::TYPE_STRING:
      out << "\"" << value->get_string() << "\"";
      break;
    case t_base_type::TYPE_BOOL:
      out << (value->get_integer() > 0 ? "t" : "nil");
      break;
    case t_base_type::TYPE_BYTE:
    case t_base_type::TYPE_I16:
    case t_base_type::TYPE_I32:
    case t_base_type::TYPE_I64:
      out << value->get_integer();
      break;
    case t_base_type::TYPE_DOUBLE:
      if (value->get_type() == t_const_value::CV_INTEGER) {
        out << value->get_integer();
      } else {
        out << value->get_double();
      }
      break;
    default:
      throw "compiler error: no const of base type " + t_base_type::t_base_name(tbase);
    }
  } else if (type->is_enum()) {
    indent(out) << value->get_integer();
  } else if (type->is_struct() || type->is_xception()) {
    out << (type->is_struct() ? "(make-instance '" : "(make-exception '") <<
           lowercase(type->get_name()) << " " << endl;
    indent_up();

    const vector<t_field*>& fields = ((t_struct*)type)->get_members();
    vector<t_field*>::const_iterator f_iter;
    const map<t_const_value*, t_const_value*>& val = value->get_map();
    map<t_const_value*, t_const_value*>::const_iterator v_iter;

    for (v_iter = val.begin(); v_iter != val.end(); ++v_iter) {
      t_type* field_type = NULL;
      for (f_iter = fields.begin(); f_iter != fields.end(); ++f_iter) {
        if ((*f_iter)->get_name() == v_iter->first->get_string()) {
          field_type = (*f_iter)->get_type();
        }
      }
      if (field_type == NULL) {
        throw "type error: " + type->get_name() + " has no field " + v_iter->first->get_string();
      }

      out << indent() << ":" << v_iter->first->get_string() << " " <<
        render_const_value(field_type, v_iter->second) << endl;
    }
    out << indent() << ")";

    indent_down();
  } else if (type->is_map()) {
    // emit an hash form with both keys and values to be evaluated
    t_type* ktype = ((t_map*)type)->get_key_type();
    t_type* vtype = ((t_map*)type)->get_val_type();
    out << "(thrift:map ";
    indent_up();
    const map<t_const_value*, t_const_value*>& val = value->get_map();
    map<t_const_value*, t_const_value*>::const_iterator v_iter;
    for (v_iter = val.begin(); v_iter != val.end(); ++v_iter) {
      out << endl << indent()
          << "(cl:cons " << render_const_value(ktype, v_iter->first) << " "
          << render_const_value(vtype, v_iter->second) << ")";
    }
    indent_down();
    out << indent() << ")";
  } else if (type->is_list() || type->is_set()) {
    t_type* etype;
    if (type->is_list()) {
      etype = ((t_list*)type)->get_elem_type();
    } else {
      etype = ((t_set*)type)->get_elem_type();
    }
    if (type->is_set()) {
      out << "(thrift:set" << endl;
    } else {
      out << "(thrift:list" << endl;
    }
    indent_up();
    indent_up();
    const vector<t_const_value*>& val = value->get_list();
    vector<t_const_value*>::const_iterator v_iter;
    for (v_iter = val.begin(); v_iter != val.end(); ++v_iter) {
      out << indent() << render_const_value(etype, *v_iter) << endl;
    }
    out << indent() << ")";
    indent_down();
    indent_down();
  } else {
    throw "CANNOT GENERATE CONSTANT FOR TYPE: " + type->get_name();
  }
  return out.str();
}

void t_cl_generator::generate_struct(t_struct* tstruct) {
  generate_cl_struct(f_types_, tstruct, false);
}

void t_cl_generator::generate_xception(t_struct* txception) {
  generate_cl_struct(f_types_, txception, true);
}

void t_cl_generator::generate_cl_struct_internal(std::ofstream& out, t_struct* tstruct, bool is_exception) {
  const vector<t_field*>& members = tstruct->get_members();
  vector<t_field*>::const_iterator m_iter;

  out << "(";

  for (m_iter = members.begin(); m_iter != members.end(); ++m_iter) {
    t_const_value* value = (*m_iter)->get_value();
    t_type* type = (*m_iter)->get_type();

    if (m_iter != members.begin()) {
      out << endl << indent() << " ";
    }
    out << "(" << prefix((*m_iter)->get_name()) << " " <<
        ( (NULL != value) ? render_const_value(type, value) : "nil" ) <<
        " :type " << typespec((*m_iter)->get_type()) <<
        " :id " << (*m_iter)->get_key();
    if ( (*m_iter)->has_doc()) {
      out << " :documentation \"" << cl_docstring((*m_iter)->get_doc()) << "\"";
    }
    out <<")";
  }

  out << ")";
}

void t_cl_generator::generate_cl_struct(std::ofstream& out, t_struct* tstruct, bool is_exception = false) {
  std::string name = type_name(tstruct);
  out << (is_exception ? "(thrift:def-exception " : "(thrift:def-struct ") <<
      prefix(name) << endl;
  indent_up();
  if ( tstruct->has_doc() ) {
    out << indent() ;
    out << "\"" << cl_docstring(tstruct->get_doc()) << "\"" << endl;
  }
  out << indent() ;
  generate_cl_struct_internal(out, tstruct, is_exception);
  indent_down();
  out << ")" << endl << endl;
}

void t_cl_generator::generate_exception_sig(std::ofstream& out, t_function* f) {
  generate_cl_struct_internal(out, f->get_xceptions(), true);
}

void t_cl_generator::generate_service(t_service* tservice) {
  string extends_client;
  vector<t_function*> functions = tservice->get_functions();
  vector<t_function*>::iterator f_iter;

  if (tservice->get_extends() != NULL) {
    extends_client = type_name(tservice->get_extends());
  }

  extends_client = extends_client.empty() ? "nil" : prefix(extends_client);

  f_types_ << "(thrift:def-service " << prefix(service_name_) << " "
           << extends_client;

  indent_up();

  if ( tservice->has_doc()) {
      f_types_ << endl << indent()
               << "(:documentation \"" << cl_docstring(tservice->get_doc()) << "\")";
    }

  for (f_iter = functions.begin(); f_iter != functions.end(); ++f_iter) {
    t_function* function = *f_iter;
    string fname = function->get_name();
    string signature = function_signature(function);
    t_struct* exceptions = function->get_xceptions();
    const vector<t_field*>& xmembers = exceptions->get_members();

    f_types_ << endl << indent() << "(:method " << prefix(fname);
    f_types_ << " (" << signature << " "  << typespec((*f_iter)->get_returntype()) << ")";
    if (xmembers.size() > 0) {
      f_types_ << endl << indent() << " :exceptions " ;
      generate_exception_sig(f_types_, function);
    }
    if ( (*f_iter)->is_oneway() ) {
      f_types_ << endl << indent() << " :oneway t";
    }
    f_types_ << ")";
  }

  f_types_ << ")" << endl;

  indent_down();
}

string t_cl_generator::typespec(t_type *t) {
  t = get_true_type(t);

  if (t->is_base_type()) {
    return type_name(t);
  } else if (t->is_map()) {
    t_map *m = (t_map*) t;
    return "(map " + typespec(m->get_key_type()) + " " + 
      typespec(m->get_val_type()) + ")";
  } else if (t->is_struct() || t->is_xception()) {
    return "(struct " + prefix(type_name(t)) + ")";
  } else if (t->is_list()) {
    return "(list " + typespec(((t_list*) t)->get_elem_type()) + ")";
  } else if (t->is_set()) {
    return "(set " + typespec(((t_set*) t)->get_elem_type()) + ")";
  } else if (t->is_enum()) {
    return "(enum \"" + ((t_enum*) t)->get_name() + "\")";
  } else {
    throw "Sorry, I don't know how to generate this: " + type_name(t);
  }
}

string t_cl_generator::function_signature(t_function* tfunction) {
  return argument_list(tfunction->get_arglist());
}

string t_cl_generator::argument_list(t_struct* tstruct) {
  stringstream res;
  res << "(";

  const vector<t_field*>& fields = tstruct->get_members();
  vector<t_field*>::const_iterator f_iter;
  bool first = true;
  for (f_iter = fields.begin(); f_iter != fields.end(); ++f_iter) {
    if (first) {
      first = false;
    } else {
      res << " ";
    }
    res << "(" + prefix((*f_iter)->get_name()) << " " <<
      typespec((*f_iter)->get_type()) << " " <<
      (*f_iter)->get_key() <<  ")";

    
  }
  res << ")";
  return res.str();
}

string t_cl_generator::type_name(t_type* ttype) {
  string prefix = "";
  t_program* program = ttype->get_program();

  if (program != NULL && program != program_)
    prefix = package_of(program) == package() ? "" : package_of(program) + ":";

  string name = ttype->get_name();

  if (ttype->is_struct() || ttype->is_xception())
    name = lowercase(ttype->get_name());

  return prefix + name;
}

THRIFT_REGISTER_GENERATOR(cl, "Common Lisp", "");
