package org.jetbrains.bazel.languages.bazelrc.psi

import com.intellij.lang.ASTNode
import com.intellij.psi.PsiElement
import org.jetbrains.bazel.languages.bazelrc.elements.BazelrcTokenTypes

class BazelrcLine(node: ASTNode) : BazelrcBaseElement(node) {
  override fun acceptVisitor(visitor: BazelrcElementVisitor) = visitor.visitLine(this)

  fun configName(): String? = this.findChildByType<PsiElement>(BazelrcTokenTypes.CONFIG)?.text
}
