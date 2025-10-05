from django.db import models
from django.utils import timezone


class GeocodedAddress(models.Model):
    address = models.CharField(
        'Адрес',
        max_length=200,
        unique=True,
        db_index=True
    )
    latitude = models.FloatField(
        'Широта',
        null=True,
        blank=True,
        help_text='Широта полученная от геокодера'
    )
    longitude = models.FloatField(
        'Долгота',
        null=True,
        blank=True,
        help_text='Долгота полученная от геокодера'
    )
    queried_at = models.DateTimeField(
        'Дата запроса к геокодеру',
        default=timezone.now,
        help_text='Дата последнего успешного запроса к геокодеру для этого адреса'
    )

    class Meta:
        verbose_name = 'Геокодированный адрес'
        verbose_name_plural = 'Геокодированные адреса'

    def __str__(self):
        return self.address
