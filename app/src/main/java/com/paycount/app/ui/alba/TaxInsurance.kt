package com.paycount.app.ui.alba

/** 세금 설정(단일 소스) */
sealed interface TaxConfig {
    data object NONE : TaxConfig
    data object Biz33 : TaxConfig            // 3.3%
    data object Day66 : TaxConfig            // 6.6%
    data class CustomPercent(val percent: Double) : TaxConfig
}

/** 보험 설정(단일 소스) */
sealed interface InsuranceConfig {
    data object NONE : InsuranceConfig
    data object EmploymentOnly : InsuranceConfig
    data object Four : InsuranceConfig
}
