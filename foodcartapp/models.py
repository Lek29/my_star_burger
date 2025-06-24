from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.db.models import DecimalField, F, Prefetch, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone
from geopy.distance import great_circle
from phonenumber_field.modelfields import PhoneNumberField

from geocoordinates.models import GeocodedAddress
from geocoordinates.utils import fetch_coordinates
from geocoordinates.utils import get_or_create_geocoded_address


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
    geocoded_address = models.ForeignKey(
        GeocodedAddress,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='related_restaurants',
        verbose_name='Геокодированный адрес ресторана'
    )

    def save(self, *args, **kwargs):
        if not self.pk or self.address != self.__original_address or not self.geocoded_address_id:
            self.geocoded_address = get_or_create_geocoded_address(self.address)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.__original_address = self.address if self.pk else None


    def get_distance_to(self, address):
        if not self.geocoded_address or self.geocoded_address.latitude is None or self.geocoded_address.longitude is None:
            return float('inf')

        if not address or address.latitude is None or address.longitude is None:
            return float('inf')

        rest_lat, rest_lon = self.geocoded_address.latitude, self.geocoded_address.longitude
        order_lat, order_lon = address.latitude, address.longitude

        distance_km = great_circle((order_lat, order_lon), (rest_lat, rest_lon)).km
        return round(distance_km, 1)

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
        verbose_name='ресторан',
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
        return f'{self.restaurant.name} - {self.product.name}'


class OrderQuerySet(models.QuerySet):
    """ Кастомный QuerySet для модели Order"""
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

    def prefetch_available_restaurants(self):
        return self.prefetch_related(
            Prefetch(
                'items__product__menu_items',
                queryset=RestaurantMenuItem.objects.filter(availability=True),
                to_attr='available_product_menu_items'
            )
        )

    def get_matching_restaurants_for_order(self, order):
        if not order.items.exists():
            return []

        if not order.delivery_address:
            return []

        restaurants_for_each_product = []
        for item in order.items.all():
            available_restaurants = [
                menu_item.restaurant
                for menu_item in getattr(item.product, 'available_product_menu_items', [])
            ]
            if not available_restaurants:
                return []
            restaurants_for_each_product.append(set(available_restaurants))

        if not restaurants_for_each_product:
            return []

        suitable_restaurants_set = set.intersection(*restaurants_for_each_product)

        delivery_coords = fetch_coordinates(settings.YANDEX_GEOCODER_API_KEY, order.delivery_address)
        if not delivery_coords:
            return []

        delivery_lat, delivery_lon = float(delivery_coords[1]), float(delivery_coords[0])

        restaurants_with_distance = []
        for restaurant in suitable_restaurants_set:
            restaurant_coords = fetch_coordinates(settings.YANDEX_GEOCODER_API_KEY, restaurant.address)

            if not restaurant_coords:
                continue

            restaurant_lon, restaurant_lat = float(restaurant_coords[0]), float(restaurant_coords[1])

            distance = great_circle(
                (delivery_lat, delivery_lon),
                (restaurant_lat, restaurant_lon)
            ).km

            restaurant.distance = round(distance)
            restaurants_with_distance.append(restaurant)

        sorted_restaurants = sorted(
            [r for r in restaurants_with_distance if hasattr(r, 'distance')],
            key=lambda r: r.distance
        )
        return sorted_restaurants


class PaymentMethod(models.TextChoices):
    CASH = 'cash', 'Наличными при получении'
    CARD = 'card', 'Электронно'


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
    delivery_address = models.CharField(
        'Адрес доставки',
        max_length=200,
    )
    geocoded_delivery_address = models.ForeignKey(
        GeocodedAddress,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='related_orders',
        verbose_name='Геокодированный адрес доставки'
    )
    status = models.CharField(
        'Статус заказов',
        max_length=50,
        choices=ORDER_STATUSES,
        default=STATUS_NEW,
        db_index=True,
    )
    payment_method = models.CharField(
        'Способ оплаты',
        max_length=50,
        choices=PaymentMethod.choices,
        db_index=True,
    )
    customer_comment = models.TextField(
        'Комментарий',
        blank=True,
        null=True,
        help_text='Примечания к заказу'
    )
    restaurant = models.ForeignKey(
        Restaurant,
        verbose_name='Готовит ресторан',
        related_name='orders',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_index=True,
    )

    objects = OrderQuerySet.as_manager()

    def save(self, *args, **kwargs):
        if not self.pk or self.delivery_address != self.__original_delivery_address or not self.geocoded_delivery_address_id:
            self.geocoded_delivery_address = get_or_create_geocoded_address(self.delivery_address)
        super().save(*args, **kwargs)


    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.__original_delivery_address = self.delivery_address if self.pk else None

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
        return f'{self.quantity} x {self.product.name} для заказа №{self.order.id}'
