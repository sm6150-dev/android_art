// Copyright 2011 Google Inc. All Rights Reserved.

#ifndef ART_SRC_CLASS_LINKER_H_
#define ART_SRC_CLASS_LINKER_H_

#include <map>
#include <utility>
#include <vector>

#include "dex_file.h"
#include "heap.h"
#include "intern_table.h"
#include "macros.h"
#include "object.h"
#include "thread.h"
#include "unordered_map.h"

#include "gtest/gtest.h"

namespace art {

class ClassLinker {
 public:
  // Initializes the class linker.
  static ClassLinker* Create(const std::vector<DexFile*>& boot_class_path);

  ~ClassLinker() {}

  // Finds a class by its descriptor name.
  // If class_loader is null, searches boot_class_path_.
  Class* FindClass(const StringPiece& descriptor,
                   ClassLoader* class_loader);

  Class* FindSystemClass(const StringPiece& descriptor) {
    return FindClass(descriptor, NULL);
  }

  bool InitializeClass(Class* klass);

  void RegisterDexFile(const DexFile* dex_file);

  void VisitRoots(Heap::RootVistor* root_visitor, void* arg);

 private:
  ClassLinker() {
    classes_lock_ = Mutex::Create("ClassLinker::Lock");
  }

  void Init(const std::vector<DexFile*>& boot_class_path_);

  // For early bootstrapping by Init
  Class* AllocClass(Class* java_lang_Class);

  // Alloc* convenience functions to avoid needing to pass in Class*
  // values that are known to the ClassLinker such as
  // kObjectArrayClass and kJavaLangString etc.
  Class* AllocClass();
  DexCache* AllocDexCache();
  Field* AllocField();
  Method* AllocMethod();
  template <class T>
  ObjectArray<T>* AllocObjectArray(size_t length) {
    return ObjectArray<T>::Alloc(class_roots_->Get(kObjectArrayClass), length);
  }
  PathClassLoader* AllocPathClassLoader(std::vector<const DexFile*> dex_files);

  Class* CreatePrimitiveClass(const StringPiece& descriptor);

  Class* CreateArrayClass(const StringPiece& descriptor,
                          ClassLoader* class_loader);

  Class* FindPrimitiveClass(char type);

  const DexFile& FindDexFile(const DexCache* dex_cache) const;

  DexCache* FindDexCache(const DexFile* dex_file) const;

  void AppendToBootClassPath(DexFile* dex_file);

  void LoadClass(const DexFile& dex_file,
                 const DexFile::ClassDef& dex_class_def,
                 Class* klass,
                 ClassLoader* class_loader);

  void LoadInterfaces(const DexFile& dex_file,
                      const DexFile::ClassDef& dex_class_def,
                      Class *klass);

  void LoadField(const DexFile& dex_file,
                 const DexFile::Field& dex_field,
                 Class* klass,
                 Field* dst);

  void LoadMethod(const DexFile& dex_file,
                  const DexFile::Method& dex_method,
                  Class* klass,
                  Method* dst);

  Class* ResolveClass(const Class* referring,
                      uint32_t class_idx,
                      const DexFile& dex_file);

  String* ResolveString(const Class* referring,
                        uint32_t string_idx,
                        const DexFile& dex_file);

  Class* LookupClass(const StringPiece& descriptor, ClassLoader* class_loader);

  // Inserts a class into the class table.  Returns true if the class
  // was inserted.
  bool InsertClass(Class* klass);

  bool InitializeSuperClass(Class* klass);

  void InitializeStaticFields(Class* klass);

  bool ValidateSuperClassDescriptors(const Class* klass);

  bool HasSameDescriptorClasses(const char* descriptor,
                                const Class* klass1,
                                const Class* klass2);

  bool HasSameMethodDescriptorClasses(const Method* descriptor,
                                      const Class* klass1,
                                      const Class* klass2);

  bool LinkClass(Class* klass, const DexFile& dex_file);

  bool LinkSuperClass(Class* klass);

  bool LoadSuperAndInterfaces(Class* klass, const DexFile& dex_file);

  bool LinkMethods(Class* klass);

  bool LinkVirtualMethods(Class* klass);

  bool LinkInterfaceMethods(Class* klass);

  void LinkAbstractMethods(Class* klass);

  bool LinkStaticFields(Class* klass);

  bool LinkInstanceFields(Class* klass);

  void CreateReferenceOffsets(Class* klass);

  std::vector<const DexFile*> boot_class_path_;

  std::vector<const DexFile*> dex_files_;

  std::vector<DexCache*> dex_caches_;

  // multimap from String::descriptor_ to Class* instances. Results
  // should be compared for a matching Class::descriptor_ and
  // Class::class_loader_.
  typedef std::tr1::unordered_multimap<StringPiece, Class*> Table;
  Table classes_;
  Mutex* classes_lock_;

  InternTable intern_table_;

  // indexes into class_roots_
  enum ClassRoot {
    kJavaLangClass,
    kJavaLangObject,
    kObjectArrayClass,
    kJavaLangString,
    kCharArrayClass,
    kIntArrayClass,
    kLongArrayClass,
    kJavaLangReflectField,
    kJavaLangReflectMethod,
    kJavaLangClassLoader,
    kDalvikSystemBaseDexClassLoader,
    kDalvikSystemPathClassLoader,
    kPrimitiveBoolean,
    kPrimitiveChar,
    kPrimitiveFloat,
    kPrimitiveDouble,
    kPrimitiveByte,
    kPrimitiveShort,
    kPrimitiveInt,
    kPrimitiveLong,
    kPrimitiveVoid,
    kClassRootsMax,
  };
  ObjectArray<Class>* class_roots_;

  Class* GetClassRoot(ClassRoot class_root) {
    Class* klass = class_roots_->Get(class_root);
    DCHECK(klass != NULL);
    return klass;
  }

  ObjectArray<Class>* array_interfaces_;
  InterfaceEntry* array_iftable_;

  bool init_done_;

  friend class RuntimeTest;
  FRIEND_TEST(DexCacheTest, Open);
  friend class ObjectTest;
  FRIEND_TEST(ObjectTest, AllocObjectArray);
  DISALLOW_COPY_AND_ASSIGN(ClassLinker);
};

}  // namespace art

#endif  // ART_SRC_CLASS_LINKER_H_
