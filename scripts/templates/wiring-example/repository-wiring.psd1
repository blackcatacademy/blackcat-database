@{
  Repositories = @(
    @{
      Alias   = 'payments'
      Class   = 'BlackCat\Database\Packages\Orders\Repository\PaymentsRepository'
      VarName = 'paymentsRepo'  # bez $
      Import  = 'use BlackCat\Database\Packages\Orders\Repository\PaymentsRepository;'
    }
  )
}
