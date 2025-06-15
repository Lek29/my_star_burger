from django.db import models
from django.db.models import Sum, F, DecimalField
from django.db.models.functions import Coalesce
from django.core.validators import MinValueValidator
from phonenumber_field.modelfields import PhoneNumberField

class Restaurant(models.Model):
    name = models.CharField(
        'название',
        max_length=50
    )
    address = models.CharField(
        'адрес',
        max_length=100,
        blank=True,
    )
    contact_phone = models.CharField(
        'контактный телефон',
        max_length=50,
        blank=True,
    )

    class Meta:
        verbose_name = 'ресторан'
        verbose_name_plural = 'рестораны'

    def __str__(self):
        return self.name


class ProductQuerySet(models.QuerySet):
    def available(self):
        products = (
            RestaurantMenuItem.objects
            .filter(availability=True)
            .values_list('product')
        )
        return self.filter(pk__in=products)


class ProductCategory(models.Model):
    name = models.CharField(
        'название',
        max_length=50
    )

    class Meta:
        verbose_name = 'категория'
        verbose_name_plural = 'категории'

    def __str__(self):
        return self.name


class Product(models.Model):
    name = models.CharField(
        'название',
        max_length=50
    )
    category = models.ForeignKey(
        ProductCategory,
        verbose_name='категория',
        related_name='products',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    price = models.DecimalField(
        'цена',
        max_digits=8,
        decimal_places=2,
        validators=[MinValueValidator(0)]
    )
    image = models.ImageField(
        'картинка'
    )
    special_status = models.BooleanField(
        'спец.предложение',
        default=False,
        db_index=True,
    )
    description = models.TextField(
        'описание',
        max_length=200,
        blank=True,
    )

    objects = ProductQuerySet.as_manager()

    class Meta:
        verbose_name = 'товар'
        verbose_name_plural = 'товары'

    def __str__(self):
        return self.name


class RestaurantMenuItem(models.Model):
    restaurant = models.ForeignKey(
        Restaurant,
        related_name='menu_items',
        verbose_name="ресторан",
        on_delete=models.CASCADE,
    )
    product = models.ForeignKey(
        Product,
        on_delete=models.CASCADE,
        related_name='menu_items',
        verbose_name='продукт',
    )
    availability = models.BooleanField(
        'в продаже',
        default=True,
        db_index=True
    )

    class Meta:
        verbose_name = 'пункт меню ресторана'
        verbose_name_plural = 'пункты меню ресторана'
        unique_together = [
            ['restaurant', 'product']
        ]

    def __str__(self):
        return f"{self.restaurant.name} - {self.product.name}"



class OrderQuerySet(models.QuerySet):
    ' Кастомный QuerySet для модели Order'
    def annotate_with_total_cost(self):
        cost_per_items = F('items__quantity') * F('items__price_at_purchase')
        sum_of_items_coast = Sum(
            cost_per_items,
            output_field=DecimalField(max_digits=10, decimal_places=2)
        )
        annotated_queryset = self.annotate(
            total_order_cost=Coalesce(
                sum_of_items_coast,
                0,
                output_field=DecimalField(max_digits=10, decimal_places=2)
            )
        )
        return annotated_queryset


class Order(models.Model):
    STATUS_NEW = 'NEW'
    STATUS_PREPARING = 'PREPARING'
    STATUS_DELIVERING = 'DELIVERING'
    STATUS_COMPLETED = 'COMPLETED'
    STATUS_CANCELED = 'CANCELED'

    ORDER_STATUSES = [
        (STATUS_NEW, 'Необработан'),
        (STATUS_PREPARING, 'Готовится'),
        (STATUS_DELIVERING, 'В доставке'),
        (STATUS_COMPLETED, 'Выполнен'),
        (STATUS_CANCELED, 'Отменён'),
    ]
    created_at = models.DateTimeField(
        'Дата создания',
        auto_now_add=True,
        db_index=True,
    )
    called_at = models.DateTimeField(
        'Дата звонка',
        blank=True,
        null=True,
        db_index=True,
    )
    delivered_at = models.DateTimeField(
        'Дата доставки',
        blank=True,
        null=True,
        db_index=True,
    )
    client_name = models.CharField(
        'Имя',
        max_length=50,
    )
    surname = models.CharField(
        'Фамилия',
        max_length=50,
        blank=True,
    )
    phone = PhoneNumberField(
        'Телефон',
        region='RU',
        db_index=True,
    )
    delivery_address=models.CharField(
        'Адрес доставки',
        max_length=200,
    )
    status=models.CharField(
        'Статус заказов',
        max_length=50,
        choices=ORDER_STATUSES,
        default=STATUS_NEW,
        db_index=True,
    )
    customer_comment =models.TextField(
        'Комментарий',
        blank=True,
        null=True,
        help_text='Примечания к заказу'
    )

    objects = OrderQuerySet.as_manager()
    class Meta:
        ordering = ['id']
        verbose_name = 'заказ'
        verbose_name_plural = 'заказы'

    def __str__(self):
        return f'Заказ № {self.id} от {self.client_name} {self.surname if self.surname else ""}'


class OrderItem(models.Model):
    order = models.ForeignKey(
        Order,
        on_delete=models.CASCADE,
        related_name='items',
        verbose_name='Заказ'
    )
    product = models.ForeignKey(
        Product,
        on_delete=models.PROTECT,
        related_name='order_items',
        verbose_name='Товар'
    )
    quantity = models.PositiveIntegerField(
        'Количество',
        validators=[MinValueValidator(1)]
    )
    price_at_purchase = models.DecimalField(
        'Цена товара в заказе',
        max_digits=8,
        decimal_places=2,
        validators=[MinValueValidator(0)]
    )

    class Meta:
        verbose_name = 'позиция заказа'
        verbose_name_plural = 'позиции заказа'
        unique_together = [['order', 'product']]

    def __str__(self):
        return f"{self.quantity} x {self.product.name} для заказа №{self.order.id}"



